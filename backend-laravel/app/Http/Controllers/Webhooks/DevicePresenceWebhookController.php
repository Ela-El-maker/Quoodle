<?php

namespace App\Http\Controllers\Webhooks;

use App\Http\Controllers\Controller;
use App\Models\Device;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class DevicePresenceWebhookController extends Controller
{
    public function online(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'device_id' => ['required', 'string'],
            'session_id' => ['required', 'string'],
            'agent_version' => ['nullable', 'string'],
            'os_build' => ['nullable', 'string'],
            'attestation_hash' => ['nullable', 'string'],
            'connected_at' => ['required', 'string'],
        ]);

        if ($validator->fails()) {
            return response()->json(['status' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $data = $validator->validated();

        $device = Device::firstOrCreate(['device_id' => $data['device_id']], [
            'device_name' => $data['device_id'],
        ]);

        $device->update([
            'last_seen' => $data['connected_at'],
            'agent_version' => $data['agent_version'],
            'os_build' => $data['os_build'],
            'policy_hash' => $device->policy_hash,
            'lifecycle_state' => 'active',
        ]);

        return response()->json(['status' => 'ack']);
    }

    public function offline(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'device_id' => ['required', 'string'],
            'session_id' => ['nullable', 'string'],
            'last_seen' => ['required', 'string'],
            'reason' => ['required', 'string'],
        ]);

        if ($validator->fails()) {
            return response()->json(['status' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $data = $validator->validated();
        $device = Device::find($data['device_id']);
        if ($device) {
            $device->update([
                'last_seen' => $data['last_seen'],
                'lifecycle_state' => $data['reason'] === 'disconnect' ? 'active' : 'quarantine',
            ]);
        }

        return response()->json(['status' => 'ack']);
    }
}
