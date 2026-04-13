<?php

namespace App\Http\Controllers\Devices;

use App\Http\Controllers\Controller;
use App\Models\AuthToken;
use App\Models\Device;
use App\Models\DeviceTelemetryLatest;
use App\Models\TelemetrySnapshot;
use Illuminate\Http\JsonResponse;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class DeviceController extends Controller
{
    private function requireValidSession(string $userId, string $sessionId): bool
    {
        return AuthToken::where('user_id', $userId)
            ->where('session_id', $sessionId)
            ->whereNull('revoked_at')
            ->where('expires_at', '>', now())
            ->exists();
    }

    private function visibleDevicesQuery(Request $request): Builder
    {
        $user = $request->user();
        $query = Device::query();

        if (! $user || $user->role !== 'admin') {
            $query->where('user_id', $user?->id);
        }

        return $query;
    }

    public function index(Request $request): JsonResponse
    {
        $perPage = min((int) $request->query('per_page', 50), 200);
        $devices = $this->visibleDevicesQuery($request)
            ->with('user:id,email')
            ->paginate($perPage, ['device_id', 'user_id', 'device_name', 'lifecycle_state', 'last_seen', 'agent_version', 'os_build', 'compliance_status', 'risk_score', 'policy_hash', 'reported_policy_hash']);

        $telemetryLatestByDevice = DeviceTelemetryLatest::query()
            ->whereIn('device_id', $devices->getCollection()->pluck('device_id'))
            ->get(['device_id', 'metrics', 'policy_hash', 'presence_state', 'connection_mode'])
            ->keyBy('device_id');

        return response()->json([
            'devices' => $devices->getCollection()->map(function (Device $device) use ($telemetryLatestByDevice) {
                $latest = $telemetryLatestByDevice->get($device->device_id);
                $resolvedOsBuild = $this->resolvedOsBuild($device, $latest);
                $resolvedPresenceState = $this->resolvedPresenceState($device, $latest);
                $resolvedConnectionMode = $this->resolvedConnectionMode($latest);
                $resolvedComplianceStatus = $this->resolvedComplianceStatus($device, $latest);
                $resolvedPolicyInSync = $this->resolvedPolicyInSync($device, $latest);
                $resolvedKernelGuard = $this->resolvedKernelGuard($latest);

                return [
                    'device_id' => $device->device_id,
                    'owner_email' => $device->user?->email,
                    'device_name' => $device->device_name,
                    'lifecycle_state' => $device->lifecycle_state,
                    'last_seen' => optional($device->last_seen)?->toIso8601String(),
                    'agent_version' => $device->agent_version,
                    'os_build' => $resolvedOsBuild,
                    'compliance_status' => $resolvedComplianceStatus,
                    'risk_score' => $device->risk_score,
                    'resolved_os_build' => $resolvedOsBuild,
                    'resolved_presence_state' => $resolvedPresenceState,
                    'resolved_connection_mode' => $resolvedConnectionMode,
                    'resolved_compliance_status' => $resolvedComplianceStatus,
                    'resolved_policy_in_sync' => $resolvedPolicyInSync,
                    'kernel_guard' => $resolvedKernelGuard,
                ];
            }),
            'meta' => [
                'current_page' => $devices->currentPage(),
                'last_page' => $devices->lastPage(),
                'per_page' => $devices->perPage(),
                'total' => $devices->total(),
            ],
        ]);
    }

    /**
     * Devices seen by the backend but not yet claimed by any user.
     *
     * This aligns with the "device discovery" UX: a logged-in user can claim a device.
     */
    public function unpaired(Request $request): JsonResponse
    {
        $validator = Validator::make($request->query(), [
            'user_id' => ['required', 'string'],
            'session_id' => ['required', 'string'],
        ]);

        if ($validator->fails()) {
            return response()->json(['status' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $data = $validator->validated();
        if (! $this->requireValidSession($data['user_id'], $data['session_id'])) {
            return response()->json(['status' => 'invalid_session'], 401);
        }

        $devices = Device::whereNull('user_id')
            ->orderByDesc('updated_at')
            ->get(['device_id', 'device_name', 'lifecycle_state', 'last_seen', 'agent_version', 'os_build', 'compliance_status', 'risk_score']);

        return response()->json([
            'devices' => $devices->map(function (Device $device) {
                return [
                    'device_id' => $device->device_id,
                    'device_name' => $device->device_name,
                    'lifecycle_state' => $device->lifecycle_state,
                    'last_seen' => optional($device->last_seen)?->toIso8601String(),
                    'agent_version' => $device->agent_version,
                    'os_build' => $device->os_build,
                    'compliance_status' => $device->compliance_status ?? 'unknown',
                    'risk_score' => $device->risk_score,
                ];
            }),
        ]);
    }

    public function claim(Request $request, string $device_id): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'user_id' => ['required', 'string'],
            'session_id' => ['required', 'string'],
        ]);

        if ($validator->fails()) {
            return response()->json(['status' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $data = $validator->validated();
        if (! $this->requireValidSession($data['user_id'], $data['session_id'])) {
            return response()->json(['status' => 'invalid_session'], 401);
        }

        $device = Device::find($device_id);
        if (! $device) {
            return response()->json(['message' => 'not_found'], 404);
        }

        if (! empty($device->user_id)) {
            return response()->json(['status' => 'already_claimed'], 409);
        }

        $device->update(['user_id' => $data['user_id']]);

        return response()->json([
            'status' => 'ok',
            'device_id' => $device->device_id,
        ]);
    }

    public function show(Request $request, string $device_id): JsonResponse
    {
        $device = Device::with('user:id,email')->find($device_id);
        if (! $device) {
            return response()->json(['message' => 'not_found'], 404);
        }
        $user = $request->user();
        if (! $user || ($user->role !== 'admin' && $device->user_id !== $user->id)) {
            return response()->json(['message' => 'not_found'], 404);
        }

        $latestTelemetry = DeviceTelemetryLatest::query()->where('device_id', $device_id)->first();
        $latestSnapshot = TelemetrySnapshot::where('device_id', $device_id)->orderByDesc('timestamp')->first();

        $resolvedOsBuild = $this->resolvedOsBuild($device, $latestTelemetry);
        $resolvedPresenceState = $this->resolvedPresenceState($device, $latestTelemetry);
        $resolvedConnectionMode = $this->resolvedConnectionMode($latestTelemetry);
        $resolvedComplianceStatus = $this->resolvedComplianceStatus($device, $latestTelemetry);
        $resolvedPolicyInSync = $this->resolvedPolicyInSync($device, $latestTelemetry);
        $resolvedKernelGuard = $this->resolvedKernelGuard($latestTelemetry);

        $latestMetrics = is_array($latestTelemetry?->metrics) ? $latestTelemetry->metrics : (is_array($latestSnapshot?->metrics) ? $latestSnapshot->metrics : []);
        $latestTimestamp = $latestTelemetry?->timestamp ?? $latestSnapshot?->timestamp;

        return response()->json([
            'device_id' => $device->device_id,
            'owner_email' => $device->user?->email,
            'device_name' => $device->device_name,
            'hwid' => $device->hwid,
            'lifecycle_state' => $device->lifecycle_state,
            'last_seen' => optional($device->last_seen)?->toIso8601String(),
            'agent_version' => $device->agent_version,
            'os_build' => $resolvedOsBuild,
            'risk_score' => $device->risk_score,
            'policy_hash' => $device->policy_hash,
            'reported_policy_hash' => $device->reported_policy_hash,
            'policy_in_sync' => $resolvedPolicyInSync,
            'resolved_os_build' => $resolvedOsBuild,
            'resolved_presence_state' => $resolvedPresenceState,
            'resolved_connection_mode' => $resolvedConnectionMode,
            'resolved_compliance_status' => $resolvedComplianceStatus,
            'resolved_policy_in_sync' => $resolvedPolicyInSync,
            'kernel_guard' => $resolvedKernelGuard,
            'compliance' => [
                'status' => $resolvedComplianceStatus,
                'last_evaluated_at' => optional($device->updated_at)?->toIso8601String(),
                'reasons' => [],
            ],
            'telemetry_latest' => ($latestTelemetry || $latestSnapshot) ? [
                'cpu' => $latestMetrics['cpu'] ?? null,
                'ram' => $latestMetrics['ram'] ?? null,
                'disk_usage' => $latestMetrics['disk_usage'] ?? null,
                'risk_score' => $latestMetrics['risk_score'] ?? null,
                'policy_hash' => $latestTelemetry?->policy_hash ?? ($latestMetrics['policy_hash'] ?? null),
                'timestamp' => optional($latestTimestamp)?->toIso8601String(),
            ] : [
                'cpu' => null,
                'ram' => null,
                'disk_usage' => null,
                'risk_score' => null,
                'policy_hash' => null,
                'timestamp' => null,
            ],
        ]);
    }

    private function resolvedOsBuild(Device $device, ?DeviceTelemetryLatest $latest): ?string
    {
        $metrics = is_array($latest?->metrics) ? $latest->metrics : [];
        $fromTelemetry = isset($metrics['os_build']) && is_string($metrics['os_build']) ? trim($metrics['os_build']) : '';
        if ($fromTelemetry !== '') {
            return $fromTelemetry;
        }

        return $device->os_build;
    }

    private function resolvedPresenceState(Device $device, ?DeviceTelemetryLatest $latest): string
    {
        $presence = is_string($latest?->presence_state) ? trim($latest->presence_state) : '';
        if ($presence !== '') {
            return $presence;
        }

        return match ($device->lifecycle_state) {
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

    private function resolvedComplianceStatus(Device $device, ?DeviceTelemetryLatest $latest): string
    {
        $metrics = is_array($latest?->metrics) ? $latest->metrics : [];
        $fromTelemetry = isset($metrics['compliance_status']) && is_string($metrics['compliance_status']) ? trim($metrics['compliance_status']) : '';
        if ($fromTelemetry !== '') {
            return $fromTelemetry;
        }

        return $device->compliance_status ?? 'unknown';
    }

    private function resolvedPolicyInSync(Device $device, ?DeviceTelemetryLatest $latest): ?bool
    {
        $metrics = is_array($latest?->metrics) ? $latest->metrics : [];
        if (array_key_exists('policy_in_sync', $metrics) && is_bool($metrics['policy_in_sync'])) {
            return $metrics['policy_in_sync'];
        }

        $expected = is_string($device->policy_hash) ? trim($device->policy_hash) : '';
        $reported = is_string($latest?->policy_hash) ? trim($latest->policy_hash) : '';
        if ($reported === '') {
            $reported = is_string($device->reported_policy_hash) ? trim($device->reported_policy_hash) : '';
        }

        if ($expected === '' || $reported === '') {
            return null;
        }

        return hash_equals($expected, $reported);
    }

    private function resolvedKernelGuard(?DeviceTelemetryLatest $latest): ?bool
    {
        $metrics = is_array($latest?->metrics) ? $latest->metrics : [];
        if (array_key_exists('kernel_guard', $metrics) && is_bool($metrics['kernel_guard'])) {
            return $metrics['kernel_guard'];
        }
        if (array_key_exists('kernel_mode', $metrics) && is_bool($metrics['kernel_mode'])) {
            return $metrics['kernel_mode'];
        }

        return null;
    }

    public function rename(Request $request, string $device_id): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'new_name' => ['required', 'string', 'max:190'],
        ]);

        if ($validator->fails()) {
            return response()->json(['status' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $device = Device::find($device_id);
        if (! $device) {
            return response()->json(['message' => 'not_found'], 404);
        }

        $device->update(['device_name' => $validator->validated()['new_name']]);

        return response()->json([
            'status' => 'ok',
            'device_id' => $device->device_id,
            'device_name' => $device->device_name,
        ]);
    }
}
