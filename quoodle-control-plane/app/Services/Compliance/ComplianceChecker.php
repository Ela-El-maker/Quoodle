<?php

namespace App\Services\Compliance;

use App\Models\Device;

class ComplianceChecker
{
    public function evaluateDevice(Device $device, array $signals = []): array
    {
        $failed = [];

        if (($signals['attestation_status'] ?? 'unknown') !== 'pass') {
            $failed[] = 'attestation_failed';
        }

        if (($signals['last_update_state'] ?? '') === 'failed') {
            $failed[] = 'update_failed';
        }

        if (isset($signals['expected_policy_hash'], $signals['policy_hash']) && $signals['expected_policy_hash'] !== $signals['policy_hash']) {
            $failed[] = 'policy_hash_mismatch';
        }

        if (($signals['revocation_status'] ?? 'ok') === 'revoked') {
            $failed[] = 'certificate_revoked';
        }

        if (($signals['clock_skew_seconds'] ?? 0) > 5) {
            $failed[] = 'clock_skew';
        }

        if (($device->risk_score ?? 0) >= 90) {
            $failed[] = 'risk_exceeds_threshold';
        }

        $status = empty($failed) ? 'compliant' : 'non_compliant';

        return [
            'status' => $status,
            'failed_rules' => $failed,
            'remediation' => $this->remediation($failed),
            'evaluated_at' => now()->toIso8601String(),
        ];
    }

    private function remediation(array $failed): array
    {
        $advice = [];
        foreach ($failed as $rule) {
            $advice[] = match ($rule) {
                'attestation_failed' => 'Re-run attestation from agent',
                'update_failed' => 'Retry latest OTA or rollback',
                'policy_hash_mismatch' => 'Fetch latest policy bundle',
                'certificate_revoked' => 'Re-enroll device certificate',
                'clock_skew' => 'Sync time via NTP',
                'risk_exceeds_threshold' => 'Investigate alerts and reduce risk score',
                default => 'Review device health',
            };
        }

        return $advice;
    }
}
