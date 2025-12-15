<?php

namespace App\Services\Commands;

use App\Models\Command;
use App\Models\Device;
use App\Services\CommandRegistry\Registry;
use App\Services\Compliance\ComplianceChecker;
use App\Services\PolicyEngine\PolicyEvaluator;
use Illuminate\Support\Str;

class CommandService
{
    public function __construct(
        private readonly Registry $registry,
        private readonly PolicyEvaluator $policyEvaluator,
        private readonly ComplianceChecker $complianceChecker,
        private readonly FastAPIDispatcher $dispatcher
    ) {
    }

    public function enqueue(array $payload): array
    {
        $device = Device::find($payload['device_id']);
        if (! $device) {
            return ['status' => 'rejected', 'reason' => 'device_not_found'];
        }

        $definition = $this->registry->get($payload['method']);
        if (! $definition) {
            return ['status' => 'rejected', 'reason' => 'unknown_command'];
        }

        $validation = $definition->validate($payload['params'] ?? []);
        if (! $validation['valid']) {
            return [
                'status' => 'rejected',
                'reason' => 'invalid_params',
                'errors' => $validation['errors'],
            ];
        }

        $compliance = $this->complianceChecker->evaluateDevice($device, [
            'policy_hash' => $payload['policy_hash'] ?? null,
            'expected_policy_hash' => $device->policy_hash,
            'attestation_status' => $payload['attestation_status'] ?? 'unknown',
            'last_update_state' => $payload['last_update_state'] ?? null,
            'clock_skew_seconds' => $payload['clock_skew_seconds'] ?? 0,
        ]);

        if ($compliance['status'] === 'non_compliant' && $definition->riskLevel !== 'low') {
            return ['status' => 'rejected', 'reason' => 'compliance_failed', 'compliance' => $compliance];
        }

        $policy = $this->policyEvaluator->evaluate([
            'user_id' => $payload['user_id'] ?? 'unknown',
            'user_role' => $payload['user_role'] ?? 'user',
            'device_lifecycle_state' => $device->lifecycle_state,
            'policy_hash' => $payload['policy_hash'] ?? null,
            'expected_policy_hash' => $device->policy_hash,
            'two_factor_verified' => ! empty($payload['two_factor_code']),
        ], $definition, $device);

        if ($policy['decision'] === 'deny') {
            return ['status' => 'rejected', 'reason' => $policy['reason'], 'policy' => $policy];
        }

        if ($policy['decision'] === 'require_2fa' && empty($payload['two_factor_code'])) {
            return ['status' => 'require_2fa', 'reason' => '2fa_required', 'policy' => $policy];
        }

        $command = Command::create([
            'client_message_id' => $payload['client_message_id'],
            'device_id' => $payload['device_id'],
            'method' => $payload['method'],
            'params' => $payload['params'] ?? [],
            'sensitive' => $payload['sensitive'] ?? false,
            'trace_id' => (string) Str::uuid(),
            'queued_at' => now(),
            'state' => 'queued',
            'status' => 'accepted',
            'execution_state' => 'queued',
        ]);

        $dispatchResult = $this->dispatcher->dispatch($command, $policy, $compliance);
        $state = match ($dispatchResult['status'] ?? 'queued') {
            'dispatched', 'queued' => 'sent',
            'device_offline' => 'queued',
            default => 'queued',
        };

        $command->update([
            'state' => $state,
            'execution_state' => $state,
            'dispatched_at' => $state === 'sent' ? now() : null,
            'reason' => $dispatchResult['reason'] ?? null,
        ]);

        return [
            'status' => 'accepted',
            'state' => $state,
            'policy' => $policy,
            'compliance' => $compliance,
            'command' => $command,
        ];
    }
}
