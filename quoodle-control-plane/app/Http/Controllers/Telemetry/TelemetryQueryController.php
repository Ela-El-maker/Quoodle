<?php

namespace App\Http\Controllers\Telemetry;

use App\Http\Controllers\Controller;
use App\Models\Alert;
use App\Models\Command;
use App\Models\Device;
use App\Models\DeviceTelemetryLatest;
use App\Models\TelemetryEvent;
use App\Models\TelemetryRollup;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Cache;

class TelemetryQueryController extends Controller
{
    public function latest(Request $request, string $device_id): JsonResponse
    {
        if (! $this->canViewDevice($request, $device_id)) {
            return response()->json(['message' => 'not_found'], 404);
        }

        $device = Device::query()->where('device_id', $device_id)->first();
        $latest = DeviceTelemetryLatest::query()->where('device_id', $device_id)->first();
        $resolvedOsBuild = $this->resolvedOsBuild($device, $latest);
        $resolvedPresenceState = $this->resolvedPresenceState($device, $latest);
        $resolvedConnectionMode = $this->resolvedConnectionMode($latest);
        $resolvedComplianceStatus = $this->resolvedComplianceStatus($device, $latest);
        $resolvedPolicyInSync = $this->resolvedPolicyInSync($device, $latest);
        if (! $latest) {
            return response()->json([
                'device_id' => $device_id,
                'timestamp' => null,
                'schema_version' => null,
                'session_id' => null,
                'seq' => null,
                'telemetry_scope' => null,
                'presence_state' => $resolvedPresenceState,
                'connection_mode' => $resolvedConnectionMode,
                'policy_hash' => null,
                'risk_score' => null,
                'metrics' => [],
                'masked_fields' => [],
                'resolved_os_build' => $resolvedOsBuild,
                'resolved_presence_state' => $resolvedPresenceState,
                'resolved_connection_mode' => $resolvedConnectionMode,
                'resolved_compliance_status' => $resolvedComplianceStatus,
                'resolved_policy_in_sync' => $resolvedPolicyInSync,
            ]);
        }
        $latestPresenceState = $latest->presence_state ?? $resolvedPresenceState;
        $latestConnectionMode = $latest->connection_mode ?? $resolvedConnectionMode;
        if ($latest->telemetry_scope === 'kernel_event') {
            if (! is_string($latestPresenceState) || trim($latestPresenceState) === '') {
                $latestPresenceState = 'online';
            }
            if (! is_string($latestConnectionMode) || trim($latestConnectionMode) === '') {
                $latestConnectionMode = 'wss';
            }
        }

        $metrics = is_array($latest->metrics) ? $latest->metrics : [];
        if (array_key_exists('kernel_event', $metrics) && is_array($metrics['kernel_event'])) {
            $metrics['kernel_event'] = $this->normalizeKernelEventForResponse($metrics['kernel_event']);
        }
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
            'timestamp' => optional($latest->timestamp)->toIso8601String(),
            'schema_version' => $latest->schema_version,
            'session_id' => $latest->session_id,
            'seq' => $latest->seq,
            'telemetry_scope' => $latest->telemetry_scope,
            'presence_state' => $latestPresenceState,
            'connection_mode' => $latestConnectionMode,
            'policy_hash' => $latest->policy_hash,
            'risk_score' => $latest->risk_score === null ? null : (float) $latest->risk_score,
            'metrics' => $metrics,
            'masked_fields' => $latest->masked_fields ?? [],
            'resolved_os_build' => $resolvedOsBuild,
            'resolved_presence_state' => $resolvedPresenceState,
            'resolved_connection_mode' => $resolvedConnectionMode,
            'resolved_compliance_status' => $resolvedComplianceStatus,
            'resolved_policy_in_sync' => $resolvedPolicyInSync,
        ]);
    }

    public function history(Request $request, string $device_id): JsonResponse
    {
        if (! $this->canViewDevice($request, $device_id)) {
            return response()->json(['message' => 'not_found'], 404);
        }

        $to = $this->parseTime($request->query('to')) ?? now()->utc();
        $from = $this->parseTime($request->query('from')) ?? $to->copy()->subHours(24);
        if ($from->greaterThan($to)) {
            [$from, $to] = [$to->copy()->subHours(24), $to];
        }

        $limit = min(max((int) $request->query('limit', 1000), 1), 5000);

        $events = TelemetryEvent::query()
            ->where('device_id', $device_id)
            ->whereBetween('timestamp', [$from, $to])
            ->orderBy('timestamp')
            ->limit($limit)
            ->get();
        $events = $this->dedupeKernelEvents($events);

        return response()->json([
            'device_id' => $device_id,
            'from' => $from->toIso8601String(),
            'to' => $to->toIso8601String(),
            'points' => $events->map(function (TelemetryEvent $event): array {
                $metrics = $event->metrics ?? [];
                if (array_key_exists('kernel_event', $metrics) && is_array($metrics['kernel_event'])) {
                    $metrics['kernel_event'] = $this->normalizeKernelEventForResponse($metrics['kernel_event']);
                }
                $presenceState = $this->resolvedTelemetryPresenceState($event);
                $connectionMode = $this->resolvedTelemetryConnectionMode($event);
                return [
                    'timestamp' => optional($event->timestamp)->toIso8601String(),
                    'telemetry_scope' => $event->telemetry_scope,
                    'presence_state' => $presenceState,
                    'connection_mode' => $connectionMode,
                    'risk_score' => $event->risk_score === null ? null : (float) $event->risk_score,
                    'policy_hash' => $event->policy_hash,
                    'metrics' => $metrics,
                ];
            })->values(),
        ]);
    }

    public function fleetSummary(Request $request): JsonResponse
    {
        $devices = $this->visibleDevicesQuery($request)->get(['device_id', 'lifecycle_state', 'compliance_status', 'risk_score']);
        $deviceIds = $devices->pluck('device_id');

        $latest = DeviceTelemetryLatest::query()
            ->whereIn('device_id', $deviceIds)
            ->get(['device_id', 'timestamp', 'presence_state', 'risk_score']);

        $alertsQuery = Alert::query();
        if (! $this->isAdmin($request)) {
            $alertsQuery->whereIn('device_id', $deviceIds);
        }
        $criticalAlerts = (clone $alertsQuery)->where('severity', 'critical')->count();

        $activeCommandsQuery = Command::query()->whereIn('state', ['queued', 'dispatched', 'sent', 'ack_received']);
        if (! $this->isAdmin($request)) {
            $activeCommandsQuery->whereIn('device_id', $deviceIds);
        }
        $activeCommands = $activeCommandsQuery->count();

        $statusCounts = [
            'online' => 0,
            'stale' => 0,
            'offline' => 0,
            'reconnecting' => 0,
        ];

        foreach ($latest as $row) {
            $status = in_array($row->presence_state, array_keys($statusCounts), true) ? $row->presence_state : 'offline';
            $statusCounts[$status]++;
        }

        $totalDevices = $devices->count();
        $avgRisk = $devices->avg('risk_score');
        $complianceDrift = $devices->filter(fn (Device $device) => ($device->compliance_status ?? 'unknown') !== 'compliant')->count();

        return response()->json([
            'timestamp' => now()->utc()->toIso8601String(),
            'fleet' => [
                'total_devices' => $totalDevices,
                'online' => $statusCounts['online'],
                'stale' => $statusCounts['stale'],
                'offline' => $statusCounts['offline'],
                'reconnecting' => $statusCounts['reconnecting'],
                'online_rate' => $totalDevices > 0 ? round(($statusCounts['online'] / $totalDevices) * 100, 2) : 0,
            ],
            'risk' => [
                'avg_score' => $avgRisk === null ? null : (float) $avgRisk,
                'compliance_drift_devices' => $complianceDrift,
            ],
            'alerts' => [
                'critical_total' => $criticalAlerts,
            ],
            'commands' => [
                'active_total' => $activeCommands,
            ],
        ]);
    }

    public function fleetTimeseries(Request $request): JsonResponse
    {
        $hours = min(max((int) $request->query('hours', 24), 1), 24 * 14);
        $bucket = min(max((int) $request->query('bucket_minutes', 60), 5), 60);
        $from = now()->utc()->subHours($hours);

        $deviceIds = $this->visibleDevicesQuery($request)->pluck('device_id');

        $rows = TelemetryRollup::query()
            ->whereIn('device_id', $deviceIds)
            ->where('bucket_start', '>=', $from)
            ->where('bucket_minutes', 5)
            ->orderBy('bucket_start')
            ->get();

        $series = [];
        foreach ($rows as $row) {
            $bucketStart = Carbon::parse($row->bucket_start)->second(0)->minute((int) (floor(Carbon::parse($row->bucket_start)->minute / $bucket) * $bucket));
            $key = $bucketStart->toIso8601String();
            if (! isset($series[$key])) {
                $series[$key] = [
                    'timestamp' => $key,
                    'samples' => 0,
                    'avg_cpu' => 0.0,
                    'avg_ram' => 0.0,
                    'avg_disk_usage' => 0.0,
                    'avg_risk_score' => 0.0,
                ];
            }
            $series[$key]['samples'] += 1;
            $series[$key]['avg_cpu'] += (float) ($row->avg_cpu ?? 0);
            $series[$key]['avg_ram'] += (float) ($row->avg_ram ?? 0);
            $series[$key]['avg_disk_usage'] += (float) ($row->avg_disk_usage ?? 0);
            $series[$key]['avg_risk_score'] += (float) ($row->avg_risk_score ?? 0);
        }

        $normalized = collect($series)->sortBy('timestamp')->values()->map(function (array $bucketRow): array {
            $samples = max((int) $bucketRow['samples'], 1);
            return [
                'timestamp' => $bucketRow['timestamp'],
                'avg_cpu' => round($bucketRow['avg_cpu'] / $samples, 2),
                'avg_ram' => round($bucketRow['avg_ram'] / $samples, 2),
                'avg_disk_usage' => round($bucketRow['avg_disk_usage'] / $samples, 2),
                'avg_risk_score' => round($bucketRow['avg_risk_score'] / $samples, 2),
            ];
        });

        return response()->json([
            'from' => $from->toIso8601String(),
            'to' => now()->utc()->toIso8601String(),
            'bucket_minutes' => $bucket,
            'points' => $normalized,
        ]);
    }

    public function activity(Request $request): JsonResponse
    {
        $limit = min(max((int) $request->query('limit', 50), 1), 200);
        $deviceFilter = trim((string) $request->query('device_id', ''));
        $deviceIds = $this->visibleDevicesQuery($request)->pluck('device_id');
        if ($deviceFilter !== '') {
            if (! $deviceIds->contains($deviceFilter)) {
                return response()->json(['events' => []]);
            }
            $deviceIds = collect([$deviceFilter]);
        }

        $telemetry = TelemetryEvent::query()
            ->select([
                'id',
                'device_id',
                'timestamp',
                'telemetry_scope',
                'presence_state',
                'connection_mode',
                'risk_score',
                'metrics',
            ])
            ->whereIn('device_id', $deviceIds)
            ->orderByDesc('timestamp')
            ->limit($limit)
            ->get()
            ->map(fn (TelemetryEvent $event) => [
                'id' => 'tel-'.$event->id,
                'event_type' => 'telemetry',
                'device_id' => $event->device_id,
                'timestamp' => optional($event->timestamp)->toIso8601String(),
                'detail' => [
                    'scope' => $event->telemetry_scope,
                    'presence_state' => $this->resolvedTelemetryPresenceState($event),
                    'connection_mode' => $this->resolvedTelemetryConnectionMode($event),
                    'risk_score' => $event->risk_score,
                    'kernel_event' => is_array($event->metrics)
                        ? $this->normalizeKernelEventForResponse($event->metrics['kernel_event'] ?? null)
                        : null,
                ],
            ])
            ->unique(fn (array $event) => $event['detail']['kernel_event']
                ? $this->kernelEventKeyFromArray($event['detail']['kernel_event'], $event['id'])
                : $event['id'])
            ->values();

        $alerts = Alert::query()
            ->select([
                'id',
                'device_id',
                'timestamp',
                'severity',
                'category',
                'message',
            ])
            ->whereIn('device_id', $deviceIds)
            ->orderByDesc('timestamp')
            ->limit($limit)
            ->get()
            ->map(fn (Alert $alert) => [
                'id' => 'alert-'.$alert->id,
                'event_type' => 'alert',
                'device_id' => $alert->device_id,
                'timestamp' => optional($alert->timestamp)->toIso8601String(),
                'detail' => [
                    'severity' => $alert->severity,
                    'category' => $alert->category,
                    'message' => $alert->message,
                ],
            ]);

        $commands = Command::query()
            ->select([
                'id',
                'device_id',
                'method',
                'state',
                'error_code',
                'error_message',
                'queued_at',
            ])
            ->whereIn('device_id', $deviceIds)
            ->orderByDesc('queued_at')
            ->limit($limit)
            ->get()
            ->map(fn (Command $command) => [
                'id' => 'cmd-'.$command->id,
                'event_type' => 'command',
                'device_id' => $command->device_id,
                'timestamp' => optional($command->queued_at)->toIso8601String(),
                'detail' => [
                    'method' => $command->method,
                    'state' => $command->state,
                    'error_code' => $command->error_code,
                    'error_message' => $command->error_message,
                ],
            ]);

        $events = $telemetry
            ->concat($alerts)
            ->concat($commands)
            ->sortByDesc(fn (array $event) => $event['timestamp'] ?? '')
            ->take($limit)
            ->values();

        return response()->json([
            'events' => $events,
        ]);
    }

    public function opsHealth(Request $request): JsonResponse
    {
        if (! $this->isAdmin($request)) {
            return response()->json(['message' => 'forbidden'], 403);
        }

        $recentErrors = \App\Models\TelemetryIngestError::query()
            ->where('timestamp', '>=', now()->subHour())
            ->selectRaw('reason, COUNT(*) as total')
            ->groupBy('reason')
            ->pluck('total', 'reason');

        return response()->json([
            'generated_at' => now()->utc()->toIso8601String(),
            'ingest' => [
                'accepted' => (int) Cache::get('telemetry:ingest:accepted', 0),
                'rejected' => (int) Cache::get('telemetry:ingest:rejected', 0),
                'duplicate_prevented' => (int) Cache::get('telemetry:ingest:duplicate_prevented', 0),
            ],
            'rollups' => [
                'upsert_conflict_handled' => (int) Cache::get('telemetry:rollup:upsert_conflict_handled', 0),
                'network_clamped' => (int) Cache::get('telemetry:rollup:network_clamped', 0),
            ],
            'commands' => [
                'stale_reconciled' => (int) Cache::get('commands:stale_reconciled', 0),
                'active_non_terminal' => Command::query()->whereIn('state', ['queued', 'dispatched', 'sent', 'ack_received'])->count(),
            ],
            'divergence' => [
                'os_build' => (int) Cache::get('telemetry:divergence:os_build', 0),
                'seq_non_monotonic' => (int) Cache::get('telemetry:divergence:seq_non_monotonic', 0),
            ],
            'errors_last_hour' => $recentErrors,
        ]);
    }

    private function isAdmin(Request $request): bool
    {
        return (string) ($request->user()?->role ?? '') === 'admin';
    }

    private function visibleDevicesQuery(Request $request): Builder
    {
        $query = Device::query();
        $user = $request->user();
        if (! $user || $user->role !== 'admin') {
            $query->where('user_id', $user?->id);
        }

        return $query;
    }

    private function canViewDevice(Request $request, string $deviceId): bool
    {
        return $this->visibleDevicesQuery($request)->where('device_id', $deviceId)->exists();
    }

    private function parseTime(mixed $value): ?Carbon
    {
        if (! is_string($value) || trim($value) === '') {
            return null;
        }
        try {
            return Carbon::parse($value)->utc();
        } catch (\Throwable $e) {
            return null;
        }
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

    private function normalizeKernelEventForResponse(mixed $value): ?array
    {
        if (! is_array($value)) {
            return null;
        }

        $event = $value;
        $payload = is_array($event['payload'] ?? null) ? $event['payload'] : null;
        if (! $payload) {
            $raw = is_string($event['payload_json'] ?? null) ? $event['payload_json'] : '';
            if ($raw !== '') {
                $decoded = json_decode($raw, true);
                if (is_array($decoded)) {
                    $payload = $decoded;
                }
            }
        }
        if (! $payload) {
            $payload = [];
        }

        $status = isset($payload['status']) && is_string($payload['status']) ? strtolower(trim($payload['status'])) : '';
        $errorCode = is_numeric($payload['error_code'] ?? null) ? (int) $payload['error_code'] : 0;
        $category = isset($payload['category']) && is_string($payload['category'])
            ? strtolower(trim($payload['category']))
            : 'exec';
        if (! in_array($category, ['exec', 'integrity', 'attestation', 'update', 'runtime'], true)) {
            $category = 'exec';
        }

        $payload['category'] = $category;
        $payload['subtype'] = (isset($payload['subtype']) && is_string($payload['subtype']) && trim($payload['subtype']) !== '')
            ? strtolower(trim($payload['subtype']))
            : 'opcode';
        $payload['severity'] = (isset($payload['severity']) && is_string($payload['severity']) && trim($payload['severity']) !== '')
            ? strtolower(trim($payload['severity']))
            : (($status !== '' && $status !== 'ok') || $errorCode > 0 ? 'high' : 'info');
        $payload['decision'] = (isset($payload['decision']) && is_string($payload['decision']) && trim($payload['decision']) !== '')
            ? strtolower(trim($payload['decision']))
            : (($status === 'ok' || $status === 'completed') ? 'allow' : 'deny');
        $payload['reason_code'] = (isset($payload['reason_code']) && is_string($payload['reason_code']) && trim($payload['reason_code']) !== '')
            ? strtolower(trim($payload['reason_code']))
            : ($status !== '' ? $status : 'ok');
        $payload['duration_ms'] = is_numeric($payload['duration_ms'] ?? null) ? (float) $payload['duration_ms'] : 0.0;
        $payload['queue_depth'] = is_numeric($payload['queue_depth'] ?? null) ? (int) $payload['queue_depth'] : 0;
        $payload['drop_count'] = is_numeric($payload['drop_count'] ?? null)
            ? (int) $payload['drop_count']
            : (is_numeric($payload['dropped_events'] ?? null) ? (int) $payload['dropped_events'] : 0);
        $payload['policy_ref'] = isset($payload['policy_ref']) && is_string($payload['policy_ref']) ? $payload['policy_ref'] : '';
        $payload['masked_fields'] = is_array($payload['masked_fields'] ?? null) ? $payload['masked_fields'] : [];

        $event['payload'] = $payload;
        if (! isset($event['payload_json']) || ! is_string($event['payload_json'])) {
            $event['payload_json'] = json_encode($payload, JSON_UNESCAPED_SLASHES) ?: '{}';
        }

        return $event;
    }

    private function dedupeKernelEvents(\Illuminate\Support\Collection $events): \Illuminate\Support\Collection
    {
        return $events->unique(function (TelemetryEvent $event): string {
            if ($event->telemetry_scope !== 'kernel_event') {
                return 'event:'.$event->id;
            }

            $metrics = is_array($event->metrics) ? $event->metrics : [];
            $kernel = $this->normalizeKernelEventForResponse($metrics['kernel_event'] ?? null);
            if (is_array($kernel)) {
                return $this->kernelEventKeyFromArray($kernel, (string) $event->id);
            }

            return 'kernel-fallback:'.$event->device_id.':'.($event->session_id ?? 'none').':'.((string) ($event->seq ?? 'none'));
        })->values();
    }

    private function kernelEventKeyFromArray(array $kernelEvent, string $fallback): string
    {
        $eventId = (string) ($kernelEvent['event_id'] ?? '');
        $eventType = (string) ($kernelEvent['event_type'] ?? '');
        $eventTs = (string) ($kernelEvent['event_timestamp_unix'] ?? '');
        if ($eventId === '' && $eventType === '' && $eventTs === '') {
            return $fallback;
        }

        return implode(':', ['kernel', $eventId, $eventType, $eventTs]);
    }

    private function resolvedTelemetryPresenceState(TelemetryEvent $event): ?string
    {
        $presenceState = is_string($event->presence_state) ? trim($event->presence_state) : '';
        if ($presenceState !== '') {
            return $presenceState;
        }

        if ($event->telemetry_scope === 'kernel_event') {
            return 'online';
        }

        return null;
    }

    private function resolvedTelemetryConnectionMode(TelemetryEvent $event): ?string
    {
        $connectionMode = is_string($event->connection_mode) ? trim($event->connection_mode) : '';
        if ($connectionMode !== '') {
            return $connectionMode;
        }

        if ($event->telemetry_scope === 'kernel_event') {
            return 'wss';
        }

        return null;
    }
}
