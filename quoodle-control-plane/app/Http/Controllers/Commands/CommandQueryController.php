<?php

namespace App\Http\Controllers\Commands;

use App\Http\Controllers\Controller;
use App\Models\Command;
use App\Models\Device;
use App\Services\Commands\RuntimeCapabilities;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Carbon;

class CommandQueryController extends Controller
{
    public function __construct(private readonly RuntimeCapabilities $runtimeCapabilities)
    {
    }

    public function index(Request $request): JsonResponse
    {
        $limit = min(max((int) $request->query('limit', 50), 1), 200);
        $stateFilter = $request->query('state');
        $deviceFilter = $request->query('device_id');
        $before = $request->query('before');

        $query = $this->visibleCommandsQuery($request)
            ->with(['user:id,email', 'device:device_id,device_name'])
            ->orderByDesc('queued_at')
            ->orderByDesc('id');

        if (is_string($stateFilter) && trim($stateFilter) !== '') {
            $states = array_values(array_filter(array_map('trim', explode(',', $stateFilter))));
            if (! empty($states)) {
                $query->whereIn('state', $states);
            }
        }

        if (is_string($deviceFilter) && trim($deviceFilter) !== '') {
            $query->where('device_id', $deviceFilter);
        }

        if (is_string($before) && trim($before) !== '') {
            try {
                $beforeAt = Carbon::parse($before);
                $query->where('queued_at', '<', $beforeAt);
            } catch (\Throwable $e) {
                // Ignore invalid before cursor and return first page.
            }
        }

        $commands = $query->limit($limit)->get();

        return response()->json([
            'commands' => $commands->map(fn (Command $cmd) => $this->listRow($cmd)),
            'next_before' => optional($commands->last()?->queued_at)?->toIso8601String(),
        ]);
    }

    public function capabilities(Request $request): JsonResponse
    {
        $user = $request->user();
        if (! $user) {
            return response()->json(['message' => 'unauthenticated'], 401);
        }

        $deviceId = trim((string) $request->query('device_id', ''));
        if ($deviceId !== '' && $user->role !== 'admin') {
            $visibleDevice = Device::query()
                ->where('device_id', $deviceId)
                ->where('user_id', $user->id)
                ->exists();
            if (! $visibleDevice) {
                return response()->json(['message' => 'not_found'], 404);
            }
        }

        return response()->json([
            'canonical_methods' => $this->runtimeCapabilities->canonicalMethods(),
            'runtime_supported_methods' => $this->runtimeCapabilities->runtimeSupportedMethods(),
            'rejection_reasons' => $this->runtimeCapabilities->rejectionReasonsByMethod(),
        ]);
    }

    public function show(string $command_id): JsonResponse
    {
        $command = Command::find($command_id);
        if (! $command) {
            return response()->json(['message' => 'not_found'], 404);
        }

        if (! $this->canViewCommand(request(), $command)) {
            return response()->json(['message' => 'not_found'], 404);
        }

        $this->expireIfNeeded($command);
        $command->loadMissing(['user:id,email', 'device:device_id,device_name']);

        return response()->json($this->formatCommand($command));
    }

    public function deviceCommands(Request $request, string $device_id): JsonResponse
    {
        $user = $request->user();
        if (! $user) {
            return response()->json(['message' => 'not_found'], 404);
        }
        if ($user->role !== 'admin') {
            $visibleDevice = Device::where('device_id', $device_id)
                ->where('user_id', $user->id)
                ->exists();
            if (! $visibleDevice) {
                return response()->json(['message' => 'not_found'], 404);
            }
        }

        $limit = min((int) $request->query('limit', 20), 100);
        $commands = Command::where('device_id', $device_id)
            ->with(['user:id,email', 'device:device_id,device_name'])
            ->orderByDesc('queued_at')
            ->limit($limit)
            ->get();

        return response()->json([
            'commands' => $commands->map(fn (Command $cmd) => $this->listRow($cmd)),
            'next_before' => null,
        ]);
    }

    private function visibleCommandsQuery(Request $request): Builder
    {
        $user = $request->user();
        $query = Command::query();

        if (! $user || $user->role !== 'admin') {
            $query->whereHas('device', function (Builder $deviceQuery) use ($user) {
                $deviceQuery->where('user_id', $user?->id);
            });
        }

        return $query;
    }

    private function canViewCommand(Request $request, Command $command): bool
    {
        $user = $request->user();
        if (! $user) {
            return false;
        }
        if ($user->role === 'admin') {
            return true;
        }

        $device = Device::query()
            ->where('device_id', $command->device_id)
            ->where('user_id', $user->id)
            ->exists();

        return $device;
    }

    private function listRow(Command $cmd): array
    {
        $result = $this->resultObject($cmd);
        $resultSummary = $this->resultSummary($result);

        return [
            'command_id' => $cmd->id,
            'device_id' => $cmd->device_id,
            'device_name' => $cmd->device?->device_name,
            'method' => $cmd->method,
            'params' => $cmd->params ?? [],
            'state' => $cmd->state,
            'execution_state' => $cmd->execution_state,
            'queued_at' => optional($cmd->queued_at)?->toIso8601String(),
            'dispatched_at' => optional($cmd->dispatched_at)?->toIso8601String(),
            'completed_at' => optional($cmd->completed_at)?->toIso8601String(),
            'trace_id' => $cmd->trace_id,
            'result' => $result,
            'result_status' => $resultSummary['result_status'],
            'result_notes' => $resultSummary['result_notes'],
            'artifact_url' => $resultSummary['artifact_url'],
            'artifact_checksum' => $resultSummary['artifact_checksum'],
            'error_code' => $cmd->error_code,
            'error_message' => $cmd->error_message,
            'reason' => $cmd->reason,
            'actor_email' => $cmd->user?->email,
        ];
    }

    private function formatCommand(Command $cmd): array
    {
        $result = $this->resultObject($cmd);
        $resultSummary = $this->resultSummary($result);

        return [
            'command_id' => $cmd->id,
            'device_id' => $cmd->device_id,
            'device_name' => $cmd->device?->device_name,
            'method' => $cmd->method,
            'params' => $cmd->params ?? [],
            'state' => $cmd->state,
            'execution_state' => $cmd->execution_state,
            'queued_at' => optional($cmd->queued_at)?->toIso8601String(),
            'dispatched_at' => optional($cmd->dispatched_at)?->toIso8601String(),
            'completed_at' => optional($cmd->completed_at)?->toIso8601String(),
            'trace_id' => $cmd->trace_id,
            'actor_email' => $cmd->user?->email,
            'audit' => [
                'server_seq' => $cmd->server_seq,
                'request_sig' => $cmd->request_sig,
                'envelope_sig' => $cmd->envelope_sig,
                'envelope' => $cmd->envelope,
            ],
            'result' => $result,
            'result_status' => $resultSummary['result_status'],
            'result_notes' => $resultSummary['result_notes'],
            'artifact_url' => $resultSummary['artifact_url'],
            'artifact_checksum' => $resultSummary['artifact_checksum'],
            'error_code' => $cmd->error_code,
            'error_message' => $cmd->error_message,
            'reason' => $cmd->reason,
        ];
    }

    private function resultObject(Command $command): array
    {
        return is_array($command->result) ? $command->result : [];
    }

    private function resultSummary(array $result): array
    {
        return [
            'result_status' => $result['status'] ?? null,
            'result_notes' => $result['notes'] ?? null,
            'artifact_url' => $result['artifact_url'] ?? null,
            'artifact_checksum' => $result['artifact_checksum'] ?? null,
        ];
    }

    private function expireIfNeeded(Command $command): void
    {
        if (in_array($command->state, ['completed', 'failed', 'expired', 'rejected'], true)) {
            return;
        }

        $expiresAt = $command->expires_at;
        if (! $expiresAt) {
            return;
        }

        $grace = (int) config('security.command_expiry_grace_seconds', 120);
        if (now()->greaterThan($expiresAt->copy()->addSeconds($grace))) {
            $command->update([
                'state' => 'expired',
                'execution_state' => 'expired',
                'reason' => $command->reason ?: 'ttl_expired',
                'completed_at' => now(),
            ]);
        }
    }
}
