<?php

namespace App\Http\Controllers\Devices;

use App\Http\Controllers\Controller;
use App\Models\Device;
use App\Models\TelemetrySnapshot;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class DeviceController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $devices = Device::all(['device_id', 'device_name', 'lifecycle_state', 'last_seen', 'agent_version', 'os_build', 'compliance_status', 'risk_score']);

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

    public function show(string $device_id): JsonResponse
    {
        $device = Device::find($device_id);
        if (! $device) {
            return response()->json(['message' => 'not_found'], 404);
        }

        $latestTelemetry = TelemetrySnapshot::where('device_id', $device_id)->orderByDesc('timestamp')->first();

        return response()->json([
            'device_id' => $device->device_id,
            'device_name' => $device->device_name,
            'hwid' => $device->hwid,
            'lifecycle_state' => $device->lifecycle_state,
            'last_seen' => optional($device->last_seen)?->toIso8601String(),
            'agent_version' => $device->agent_version,
            'os_build' => $device->os_build,
            'policy_hash' => $device->policy_hash,
            'compliance' => [
                'status' => $device->compliance_status ?? 'unknown',
                'last_evaluated_at' => optional($device->updated_at)?->toIso8601String(),
                'reasons' => [],
            ],
            'telemetry_latest' => $latestTelemetry ? [
                'cpu' => $latestTelemetry->metrics['cpu'] ?? null,
                'ram' => $latestTelemetry->metrics['ram'] ?? null,
                'disk_usage' => $latestTelemetry->metrics['disk_usage'] ?? null,
                'risk_score' => $latestTelemetry->metrics['risk_score'] ?? null,
                'timestamp' => optional($latestTelemetry->timestamp)?->toIso8601String(),
            ] : [
                'cpu' => null,
                'ram' => null,
                'disk_usage' => null,
                'risk_score' => null,
                'timestamp' => null,
            ],
        ]);
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
