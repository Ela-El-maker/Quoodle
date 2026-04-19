<?php

namespace App\Http\Controllers\Webhooks;

use App\Http\Controllers\Controller;
use App\Models\Device;
use App\Services\Integrations\Webhooks\OutboundWebhookPublisher;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class DevicePresenceWebhookController extends Controller
{
    public function __construct(private readonly OutboundWebhookPublisher $outboundWebhookPublisher)
    {
    }

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

        $policyHash = (string) config('policy.master_hash');
        if ($policyHash === '') {
            return response()->json(['status' => 'invalid', 'reason' => 'policy_hash_not_configured'], 500);
        }

        $device = Device::firstOrCreate(['device_id' => $data['device_id']], [
            'device_name' => $data['device_id'],
        ]);
        $previousLifecycle = (string) $device->lifecycle_state;

        $update = [
            'last_seen' => $data['connected_at'],
            'agent_version' => $data['agent_version'],
            'policy_hash' => $device->policy_hash ?: $policyHash,
            'lifecycle_state' => $data['session_id'] === 'unpaired' ? 'pending_pairing' : 'online',
        ];
        if (isset($data['os_build']) && is_string($data['os_build']) && trim($data['os_build']) !== '') {
            $update['os_build'] = trim($data['os_build']);
        }

        $device->update($update);

        if (($update['lifecycle_state'] ?? null) === 'online' && $previousLifecycle !== 'online') {
            $this->outboundWebhookPublisher->publish('device.online', [
                'device_id' => $device->device_id,
                'device_name' => $device->device_name,
                'session_id' => $data['session_id'],
                'connected_at' => $data['connected_at'],
                'agent_version' => $data['agent_version'] ?? null,
                'os_build' => $update['os_build'] ?? null,
            ]);
        }

        return response()->json(['status' => 'ack']);
    }

    public function activated(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'device_id' => ['required', 'string'],
            'session_id' => ['required', 'string'],
            'activated_at' => ['required', 'string'],
            'policy_hash' => ['nullable', 'string'],
        ]);

        if ($validator->fails()) {
            return response()->json(['status' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $data = $validator->validated();
        $device = Device::firstOrCreate(['device_id' => $data['device_id']], [
            'device_name' => $data['device_id'],
        ]);
        $previousLifecycle = (string) $device->lifecycle_state;

        $device->update([
            'last_seen' => $data['activated_at'],
            'policy_hash' => $data['policy_hash'] ?: $device->policy_hash,
            'lifecycle_state' => 'online',
        ]);

        $this->outboundWebhookPublisher->publish('device.activated', [
            'device_id' => $device->device_id,
            'device_name' => $device->device_name,
            'session_id' => $data['session_id'],
            'activated_at' => $data['activated_at'],
            'policy_hash' => $data['policy_hash'] ?: $device->policy_hash,
            'previous_lifecycle_state' => $previousLifecycle,
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
            $previousLifecycle = (string) $device->lifecycle_state;
            $reason = strtolower((string) $data['reason']);
            $state = match (true) {
                str_contains($reason, 'quarantine') || str_contains($reason, 'quarantined') => 'quarantined',
                default => 'offline',
            };
            $device->update([
                'last_seen' => $data['last_seen'],
                'lifecycle_state' => $state,
            ]);

            if ($state === 'offline' && $previousLifecycle !== 'offline') {
                $this->outboundWebhookPublisher->publish('device.offline', [
                    'device_id' => $device->device_id,
                    'device_name' => $device->device_name,
                    'last_seen' => $data['last_seen'],
                    'reason' => $data['reason'],
                    'previous_lifecycle_state' => $previousLifecycle,
                ]);
            }
        }

        return response()->json(['status' => 'ack']);
    }
}
