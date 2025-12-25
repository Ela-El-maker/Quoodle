<?php

namespace App\Services\Security;

use App\Models\Alert;
use App\Models\Command;
use App\Models\Device;
use App\Models\StateVerification;

final class StateVerifier
{
    public function registerPolicyHashCheck(Command $command, Device $device, int $delaySeconds = 10): void
    {
        // Only meaningful when an expected policy hash exists.
        if (empty($device->policy_hash)) {
            return;
        }

        StateVerification::create([
            'device_id' => $device->device_id,
            'command_id' => $command->id,
            'method' => $command->method,
            'expected_policy_hash' => $device->policy_hash,
            'not_before' => now()->addSeconds($delaySeconds),
            'status' => 'pending',
        ]);
    }

    /**
     * Process pending verifications for a device when new telemetry arrives.
     */
    public function processTelemetry(string $deviceId, ?string $reportedPolicyHash): void
    {
        $pending = StateVerification::where('device_id', $deviceId)
            ->where('status', 'pending')
            ->where('not_before', '<=', now())
            ->orderBy('created_at')
            ->get();

        if ($pending->isEmpty()) {
            return;
        }

        foreach ($pending as $v) {
            if (! empty($v->expected_policy_hash)) {
                if ($reportedPolicyHash && $reportedPolicyHash === $v->expected_policy_hash) {
                    $v->update([
                        'status' => 'ok',
                        'resolved_at' => now(),
                        'details' => 'policy_hash_in_sync',
                    ]);
                    continue;
                }

                $details = 'policy_hash_mismatch';
                $v->update([
                    'status' => 'failed',
                    'resolved_at' => now(),
                    'details' => $details,
                ]);

                // Raise a high-priority alert (truth loop violation).
                Alert::create([
                    'alert_id' => (string) \Illuminate\Support\Str::ulid(),
                    'device_id' => $deviceId,
                    'severity' => 'high',
                    'category' => 'state_verification',
                    'message' => 'State verification failed for command '.($v->command_id ?? 'unknown').": expected policy_hash={$v->expected_policy_hash} reported=".($reportedPolicyHash ?? 'null'),
                    'timestamp' => now(),
                    'acknowledged' => false,
                ]);
            }
        }
    }
}
