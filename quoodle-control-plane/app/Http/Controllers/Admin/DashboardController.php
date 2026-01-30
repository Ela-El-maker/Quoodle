<?php

namespace App\Http\Controllers\Admin;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Models\Device;
use App\Models\Command;
use App\Models\Alert;
use App\Models\AuditTrail;
use App\Models\PolicyProfile;
use App\Services\Commands\CommandService;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Redis;

class DashboardController extends Controller
{
    public function index()
    {
        // Overview stats
        $stats = [
            'total_users' => User::count(),
            'total_devices' => Device::count(),
            'active_devices' => Device::where('last_seen', '>', now()->subMinutes(5))->count(),
            'total_commands' => Command::count(),
            'pending_commands' => Command::whereNotIn('state', ['completed', 'failed', 'expired', 'rejected'])->count(),
            'total_alerts' => Alert::count(),
            'unacknowledged_alerts' => Alert::where('acknowledged', false)->count(),
            'uptime' => '99.9',
        ];

        // Recent activity
        $recentCommands = Command::with(['device', 'user'])
            ->orderBy('created_at', 'desc')
            ->limit(10)
            ->get();

        $recentAlerts = Alert::with('device')
            ->orderBy('created_at', 'desc')
            ->limit(10)
            ->get();

        $deviceStatuses = Device::select('lifecycle_state', DB::raw('count(*) as count'))
            ->groupBy('lifecycle_state')
            ->get()
            ->pluck('count', 'lifecycle_state')
            ->toArray();

        if (isset($deviceStatuses['active'])) {
            $deviceStatuses['online'] = ($deviceStatuses['online'] ?? 0) + $deviceStatuses['active'];
            unset($deviceStatuses['active']);
        }
        if (isset($deviceStatuses['quarantine']) && !isset($deviceStatuses['quarantined'])) {
            $deviceStatuses['quarantined'] = $deviceStatuses['quarantine'];
            unset($deviceStatuses['quarantine']);
        }

        return view('admin.dashboard', compact('stats', 'recentCommands', 'recentAlerts', 'deviceStatuses'));
    }

    public function users(Request $request)
    {
        $search = $request->query('q');
        $role = $request->query('role');
        $users = User::with(['devices', 'mobileDevices'])
            ->when($search, function ($query, $search) {
                $query->where('display_name', 'like', "%{$search}%")
                    ->orWhere('email', 'like', "%{$search}%")
                    ->orWhere('id', 'like', "%{$search}%");
            })
            ->when($role, fn ($query) => $query->where('role', $role))
            ->paginate(20);
        return view('admin.users.index', compact('users', 'search', 'role'));
    }

    public function devices(Request $request)
    {
        $search = $request->query('q');
        $devices = Device::with('user')
            ->when($search, function ($query, $search) {
                $query->where('device_id', 'like', "%{$search}%")
                    ->orWhere('device_name', 'like', "%{$search}%")
                    ->orWhere('os_build', 'like', "%{$search}%");
            })
            ->paginate(20);
        $fleetStats = [
            'total' => Device::count(),
            'online' => Device::whereIn('lifecycle_state', ['online', 'active'])->count(),
            'quarantined' => Device::where('compliance_status', 'quarantined')->count(),
            'at_risk' => Device::where('risk_score', '>=', 70)->count(),
        ];
        return view('admin.devices.index', compact('devices', 'fleetStats', 'search'));
    }

    public function deviceShow(Device $device)
    {
        $device->load('user');
        $recentCommands = Command::where('device_id', $device->device_id)
            ->orderBy('created_at', 'desc')
            ->limit(10)
            ->get();
        $recentAlerts = Alert::where('device_id', $device->device_id)
            ->orderBy('created_at', 'desc')
            ->limit(10)
            ->get();
        $mobileLinks = $device->links()
            ->with(['mobileDevice.user'])
            ->orderByDesc('linked_at')
            ->get();
        return view('admin.devices.show', compact('device', 'recentCommands', 'recentAlerts', 'mobileLinks'));
    }

    public function commands(Request $request)
    {
        $search = $request->query('q');
        $devices = Device::orderBy('device_name')->get();
        $commands = Command::with(['device', 'user'])
            ->when($search, function ($query, $search) {
                $query->where('id', 'like', "%{$search}%")
                    ->orWhere('method', 'like', "%{$search}%")
                    ->orWhere('device_id', 'like', "%{$search}%");
            })
            ->orderBy('created_at', 'desc')
            ->paginate(20);
        $commandStats = [
            'total' => Command::count(),
            'pending' => Command::whereNotIn('state', ['completed', 'failed', 'expired', 'rejected'])->count(),
            'completed' => Command::where('state', 'completed')->orWhere('status', 'completed')->count(),
            'failed' => Command::where('state', 'failed')->orWhere('status', 'failed')->count(),
        ];
        return view('admin.commands.index', compact('commands', 'commandStats', 'search', 'devices'));
    }

    public function commandShow(Command $command)
    {
        $command->load(['device', 'user']);
        $timeline = [
            [
                'label' => 'Intent created',
                'timestamp' => optional($command->queued_at ?? $command->created_at)->toIso8601String(),
                'status' => 'complete',
            ],
            [
                'label' => 'Dispatched',
                'timestamp' => optional($command->dispatched_at)->toIso8601String(),
                'status' => $command->dispatched_at ? 'complete' : 'pending',
            ],
            [
                'label' => 'Ack received',
                'timestamp' => null,
                'status' => in_array($command->state, ['ack_received', 'executing', 'completed', 'failed'], true) ? 'complete' : 'pending',
            ],
            [
                'label' => 'Result',
                'timestamp' => optional($command->completed_at)->toIso8601String(),
                'status' => $command->completed_at ? ($command->state === 'failed' ? 'failed' : 'complete') : ($command->state === 'executing' ? 'active' : 'pending'),
            ],
        ];

        return view('admin.commands.show', compact('command', 'timeline'));
    }

    public function commandResult(Command $command)
    {
        $command->load(['device', 'user']);
        return view('admin.commands.result', compact('command'));
    }

    public function commandExecute(Request $request, CommandService $service)
    {
        $validated = $request->validate([
            'device_id' => ['required', 'string'],
            'method' => ['required', 'string'],
            'params' => ['nullable', 'string'],
            'sensitive' => ['nullable', 'boolean'],
            'two_factor_code' => ['nullable', 'string'],
        ]);

        $params = [];
        if (! empty($validated['params'])) {
            $decoded = json_decode($validated['params'], true);
            if (json_last_error() === JSON_ERROR_NONE && is_array($decoded)) {
                $params = $decoded;
            }
        }

        $device = Device::find($validated['device_id']);
        if (! $device) {
            return redirect()->back()->withErrors(['device_id' => 'Device not found.']);
        }

        $payload = [
            'client_message_id' => (string) \Illuminate\Support\Str::uuid(),
            'device_id' => $validated['device_id'],
            'method' => $validated['method'],
            'params' => $params,
            'sensitive' => (bool) ($validated['sensitive'] ?? false),
            'two_factor_code' => $validated['two_factor_code'] ?? null,
            'user_id' => auth()->id(),
            'user_role' => auth()->user()->role ?? 'admin',
            'policy_hash' => $device->policy_hash,
        ];

        $result = $service->enqueue($payload);

        if (($result['status'] ?? '') !== 'accepted') {
            return redirect()->back()->withErrors([
                'execute' => $result['reason'] ?? 'Command rejected',
            ]);
        }

        return redirect()->route('admin.commands.show', $result['command']);
    }

    public function alerts(Request $request)
    {
        $search = $request->query('q');
        $severity = $request->query('severity');
        $status = $request->query('status');
        $alerts = Alert::with('device')
            ->when($search, function ($query, $search) {
                $query->where('message', 'like', "%{$search}%")
                    ->orWhere('category', 'like', "%{$search}%")
                    ->orWhere('device_id', 'like', "%{$search}%");
            })
            ->when($severity, fn ($query) => $query->where('severity', $severity))
            ->when($status, function ($query, $status) {
                if ($status === 'ack') {
                    $query->where('acknowledged', true);
                }
                if ($status === 'pending') {
                    $query->where('acknowledged', false);
                }
            })
            ->orderBy('created_at', 'desc')
            ->paginate(20);
        return view('admin.alerts.index', compact('alerts', 'search', 'severity', 'status'));
    }

    public function ackAlert(Alert $alert)
    {
        $alert->update([
            'acknowledged' => true,
        ]);
        return redirect()->back();
    }

    public function alertShow(Alert $alert)
    {
        $alert->load('device');
        return view('admin.alerts.show', compact('alert'));
    }

    public function audit(Request $request)
    {
        $search = $request->query('q');
        $auditLogs = AuditTrail::query()
            ->when($search, function ($query, $search) {
                $query->where('audit_id', 'like', "%{$search}%")
                    ->orWhere('device_id', 'like', "%{$search}%")
                    ->orWhere('actor', 'like', "%{$search}%")
                    ->orWhere('event_type', 'like', "%{$search}%");
            })
            ->orderBy('timestamp', 'desc')
            ->limit(200)
            ->get();
        return view('admin.audit.index', compact('auditLogs', 'search'));
    }

    public function compliance()
    {
        $profiles = PolicyProfile::orderBy('profile_id')->get();
        $nonCompliantDevices = Device::whereNotNull('compliance_status')
            ->where('compliance_status', '!=', 'compliant')
            ->orderBy('updated_at', 'desc')
            ->limit(50)
            ->get();
        return view('admin.compliance.index', compact('profiles', 'nonCompliantDevices'));
    }

    public function system()
    {
        $metrics = [
            'devices_online' => Device::whereIn('lifecycle_state', ['online', 'active'])->count(),
            'devices_total' => Device::count(),
            'commands_pending' => Command::whereNotIn('state', ['completed', 'failed', 'expired', 'rejected'])->count(),
            'commands_failed' => Command::where('state', 'failed')->count(),
            'alerts_unack' => Alert::where('acknowledged', false)->count(),
        ];

        $health = [
            'database' => $this->dbHealth(),
            'redis' => $this->redisHealth(),
            'gateway' => $this->gatewayHealth(),
            'workers' => $this->workerHealth(),
        ];

        return view('admin.system.index', compact('metrics', 'health'));
    }

    private function dbHealth(): array
    {
        try {
            DB::select('select 1');
            return ['status' => 'healthy', 'detail' => 'reachable'];
        } catch (\Throwable $e) {
            return ['status' => 'down', 'detail' => 'error'];
        }
    }

    private function redisHealth(): array
    {
        try {
            $pong = Redis::connection()->ping();
            return ['status' => 'healthy', 'detail' => $pong];
        } catch (\Throwable $e) {
            return ['status' => 'down', 'detail' => 'error'];
        }
    }

    private function gatewayHealth(): array
    {
        $url = config('services.gateway.health_url') ?? env('GATEWAY_HEALTH_URL');
        if (! $url) {
            $base = rtrim((string) config('services.fastapi.base_url'), '/');
            if ($base !== '') {
                $base = preg_replace('#/api/v1$#', '', $base);
                $url = $base.'/health';
            }
        }
        if (! $url) {
            return ['status' => 'unknown', 'detail' => 'no url'];
        }
        try {
            $resp = Http::timeout(2)->get($url);
            return ['status' => $resp->successful() ? 'healthy' : 'degraded', 'detail' => (string) $resp->status()];
        } catch (\Throwable $e) {
            return ['status' => 'down', 'detail' => 'timeout'];
        }
    }

    private function workerHealth(): array
    {
        try {
            $queue = config('queue.connections.redis.queue', 'default');
            $len = Redis::llen('queues:'.$queue);
            return [
                'status' => $len > 50 ? 'degraded' : 'healthy',
                'detail' => $len.' queued',
            ];
        } catch (\Throwable $e) {
            $pending = Command::where('state', 'queued')->orWhere('state', 'pending')->count();
            return [
                'status' => $pending > 50 ? 'degraded' : 'healthy',
                'detail' => $pending.' pending',
            ];
        }
    }

    public function exportCommands()
    {
        $commands = Command::with(['device', 'user'])->orderBy('created_at', 'desc')->limit(500)->get();
        return response()->streamDownload(function () use ($commands) {
            $out = fopen('php://output', 'w');
            fputcsv($out, ['id', 'method', 'device_id', 'device_name', 'user_id', 'user_name', 'state', 'queued_at', 'completed_at']);
            foreach ($commands as $cmd) {
                fputcsv($out, [
                    $cmd->id,
                    $cmd->method,
                    $cmd->device_id,
                    $cmd->device->device_name ?? '',
                    $cmd->user_id,
                    $cmd->user->display_name ?? '',
                    $cmd->state ?? $cmd->status,
                    optional($cmd->queued_at ?? $cmd->created_at)->toIso8601String(),
                    optional($cmd->completed_at)->toIso8601String(),
                ]);
            }
            fclose($out);
        }, 'commands.csv');
    }

    public function exportAudit()
    {
        $logs = AuditTrail::orderBy('timestamp', 'desc')->limit(1000)->get();
        return response()->streamDownload(function () use ($logs) {
            $out = fopen('php://output', 'w');
            fputcsv($out, ['timestamp', 'audit_id', 'actor', 'actor_id', 'device_id', 'event_type', 'hash', 'prev_hash']);
            foreach ($logs as $log) {
                fputcsv($out, [
                    optional($log->timestamp)->toIso8601String(),
                    $log->audit_id,
                    $log->actor,
                    $log->actor_id,
                    $log->device_id,
                    $log->event_type,
                    $log->hash,
                    $log->prev_hash,
                ]);
            }
            fclose($out);
        }, 'audit.csv');
    }

    public function exportCompliance()
    {
        $profiles = PolicyProfile::orderBy('profile_id')->get();
        $nonCompliant = Device::whereNotNull('compliance_status')
            ->where('compliance_status', '!=', 'compliant')
            ->get();
        return response()->json([
            'profiles' => $profiles,
            'non_compliant_devices' => $nonCompliant,
        ]);
    }

    public function investigations()
    {
        $latestAudit = AuditTrail::orderBy('timestamp', 'desc')->limit(15)->get();
        $latestCommands = Command::with(['device', 'user'])->orderBy('created_at', 'desc')->limit(10)->get();
        return view('admin.investigations.index', compact('latestAudit', 'latestCommands'));
    }

    public function policy()
    {
        $profiles = PolicyProfile::orderBy('profile_id')->get();
        return view('admin.policy.index', compact('profiles'));
    }
}
