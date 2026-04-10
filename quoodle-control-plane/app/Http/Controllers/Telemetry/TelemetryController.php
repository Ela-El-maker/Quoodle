<?php

namespace App\Http\Controllers\Telemetry;

use App\Http\Controllers\Controller;
use App\Models\Device;
use App\Models\DeviceTelemetryLatest;
use App\Models\TelemetryEvent;
use App\Models\TelemetrySnapshot;
use Illuminate\Support\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class TelemetryController extends Controller
{
    public function latest(string $device_id): JsonResponse
    {
        $device = Device::query()->where('device_id', $device_id)->first();
        $latest = DeviceTelemetryLatest::query()->where('device_id', $device_id)->first();
        $resolvedOsBuild = $this->resolvedOsBuild($device, $latest);
        $resolvedPresenceState = $this->resolvedPresenceState($device, $latest);
        $resolvedConnectionMode = $this->resolvedConnectionMode($latest);
        $resolvedComplianceStatus = $this->resolvedComplianceStatus($device, $latest);
        $resolvedPolicyInSync = $this->resolvedPolicyInSync($device, $latest);

        if ($latest) {
            $metrics = is_array($latest->metrics) ? $latest->metrics : [];
            if (! array_key_exists('os_build', $metrics) || ! is_string($metrics['os_build']) || trim((string) $metrics['os_build']) === '') {
                $metrics['os_build'] = $resolvedOsBuild;
            }
            if (! array_key_exists('compliance_status', $metrics) || ! is_string($metrics['compliance_status']) || trim((string) $metrics['compliance_status']) === '') {
                $metrics['compliance_status'] = $resolvedComplianceStatus;
            }
            if (! array_key_exists('policy_in_sync', $metrics) || ! is_bool($metrics['policy_in_sync'])) {
                $metrics['policy_in_sync'] = $resolvedPolicyInSync;
            }

            return response()->json([
                'device_id' => $device_id,
                'timestamp' => optional($latest->timestamp)?->toIso8601String(),
                'telemetry_scope' => $latest->telemetry_scope,
                'presence_state' => $latest->presence_state ?? $resolvedPresenceState,
                'connection_mode' => $latest->connection_mode ?? $resolvedConnectionMode,
                'metrics' => $metrics,
                'resolved_os_build' => $resolvedOsBuild,
                'resolved_presence_state' => $resolvedPresenceState,
                'resolved_connection_mode' => $resolvedConnectionMode,
                'resolved_compliance_status' => $resolvedComplianceStatus,
                'resolved_policy_in_sync' => $resolvedPolicyInSync,
            ]);
        }

        $snapshot = TelemetrySnapshot::where('device_id', $device_id)->orderByDesc('timestamp')->first();

        return response()->json([
            'device_id' => $device_id,
            'timestamp' => optional($snapshot?->timestamp)?->toIso8601String(),
            'metrics' => $snapshot?->metrics ?? [
                'cpu' => null,
                'ram' => null,
                'disk_usage' => null,
                'network_tx' => null,
                'network_rx' => null,
                'risk_score' => null,
                'policy_hash' => null,
            ],
            'resolved_os_build' => $resolvedOsBuild,
            'resolved_presence_state' => $resolvedPresenceState,
            'resolved_connection_mode' => $resolvedConnectionMode,
            'resolved_compliance_status' => $resolvedComplianceStatus,
            'resolved_policy_in_sync' => $resolvedPolicyInSync,
        ]);
    }

    public function history(Request $request, string $device_id): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'from' => ['nullable', 'date'],
            'to' => ['nullable', 'date'],
            'bucket' => ['nullable', 'string'],
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $data = $validator->validated();
        $to = isset($data['to']) ? Carbon::parse($data['to'])->utc() : now()->utc();
        $from = isset($data['from']) ? Carbon::parse($data['from'])->utc() : $to->copy()->subHours(24);
        if ($from->greaterThan($to)) {
            [$from, $to] = [$to->copy()->subHours(24), $to];
        }

        $events = TelemetryEvent::query()
            ->where('device_id', $device_id)
            ->whereBetween('timestamp', [$from, $to])
            ->orderBy('timestamp')
            ->limit(5000)
            ->get();

        if ($events->isNotEmpty()) {
            $points = $events->map(function (TelemetryEvent $event) {
                $metrics = $event->metrics ?? [];

                return [
                    'timestamp' => optional($event->timestamp)?->toIso8601String(),
                    'telemetry_scope' => $event->telemetry_scope,
                    'presence_state' => $event->presence_state,
                    'avg_cpu' => (float) ($metrics['cpu'] ?? 0),
                    'avg_ram' => (float) ($metrics['ram'] ?? 0),
                    'avg_disk_usage' => (float) ($metrics['disk_usage'] ?? 0),
                    'risk_score_avg' => (float) ($metrics['risk_score'] ?? 0),
                    'network_tx' => (float) ($metrics['network_tx'] ?? 0),
                    'network_rx' => (float) ($metrics['network_rx'] ?? 0),
                    'metrics' => $metrics,
                ];
            });
        } else {
            $points = TelemetrySnapshot::where('device_id', $device_id)
                ->whereBetween('timestamp', [$from, $to])
                ->orderBy('timestamp')
                ->limit(1000)
                ->get()
                ->map(function (TelemetrySnapshot $snap) {
                    $metrics = $snap->metrics ?? [];

                    return [
                        'timestamp' => optional($snap->timestamp)?->toIso8601String(),
                        'telemetry_scope' => null,
                        'presence_state' => null,
                        'avg_cpu' => (float) ($metrics['cpu'] ?? 0),
                        'avg_ram' => (float) ($metrics['ram'] ?? 0),
                        'avg_disk_usage' => (float) ($metrics['disk_usage'] ?? 0),
                        'risk_score_avg' => (float) ($metrics['risk_score'] ?? 0),
                        'network_tx' => (float) ($metrics['network_tx'] ?? 0),
                        'network_rx' => (float) ($metrics['network_rx'] ?? 0),
                        'metrics' => $metrics,
                    ];
                });
        }

        return response()->json([
            'device_id' => $device_id,
            'from' => $from->toIso8601String(),
            'to' => $to->toIso8601String(),
            'bucket' => $data['bucket'] ?? 'raw',
            'points' => $points,
        ]);
    }

    private function resolvedOsBuild(?Device $device, ?DeviceTelemetryLatest $latest): ?string
    {
        $metrics = is_array($latest?->metrics) ? $latest->metrics : [];
        $fromTelemetry = isset($metrics['os_build']) && is_string($metrics['os_build']) ? trim($metrics['os_build']) : '';
        if ($fromTelemetry !== '') {
            return $fromTelemetry;
        }

        return $device?->os_build;
    }

    private function resolvedPresenceState(?Device $device, ?DeviceTelemetryLatest $latest): string
    {
        $presence = is_string($latest?->presence_state) ? trim($latest->presence_state) : '';
        if ($presence !== '') {
            return $presence;
        }

        return match ($device?->lifecycle_state) {
            'online', 'active' => 'online',
            'degraded' => 'stale',
            'offline' => 'offline',
            default => 'offline',
        };
    }

    private function resolvedConnectionMode(?DeviceTelemetryLatest $latest): ?string
    {
        $mode = is_string($latest?->connection_mode) ? trim($latest->connection_mode) : '';
        return $mode === '' ? null : $mode;
    }

    private function resolvedComplianceStatus(?Device $device, ?DeviceTelemetryLatest $latest): string
    {
        $metrics = is_array($latest?->metrics) ? $latest->metrics : [];
        $fromTelemetry = isset($metrics['compliance_status']) && is_string($metrics['compliance_status']) ? trim($metrics['compliance_status']) : '';
        if ($fromTelemetry !== '') {
            return $fromTelemetry;
        }

        return $device?->compliance_status ?? 'unknown';
    }

    private function resolvedPolicyInSync(?Device $device, ?DeviceTelemetryLatest $latest): ?bool
    {
        $metrics = is_array($latest?->metrics) ? $latest->metrics : [];
        if (array_key_exists('policy_in_sync', $metrics) && is_bool($metrics['policy_in_sync'])) {
            return $metrics['policy_in_sync'];
        }

        $expected = is_string($device?->policy_hash) ? trim($device->policy_hash) : '';
        $reported = is_string($latest?->policy_hash) ? trim($latest->policy_hash) : '';
        if ($reported === '') {
            $reported = is_string($device?->reported_policy_hash) ? trim($device->reported_policy_hash) : '';
        }
        if ($expected === '' || $reported === '') {
            return null;
        }

        return hash_equals($expected, $reported);
    }
}
