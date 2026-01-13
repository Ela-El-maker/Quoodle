<?php

namespace App\Services\PolicyEngine;

use App\Models\Device;
use App\Services\CommandRegistry\CommandDefinition;

class PolicyEvaluator
{
    public function evaluate(array $context, CommandDefinition $definition, ?Device $device = null): array
    {
        $decision = 'allow';
        $reason = 'ok';

        if (! $definition->isRoleAllowed($context['user_role'] ?? '')) {
            return ['decision' => 'deny', 'reason' => 'role_not_allowed'];
        }

        if (($context['device_lifecycle_state'] ?? '') === 'quarantined' && ! $definition->allowedInQuarantine) {
            return ['decision' => 'deny', 'reason' => 'device_quarantined'];
        }

        if (($context['policy_hash'] ?? null) && ($context['expected_policy_hash'] ?? null) && $context['policy_hash'] !== $context['expected_policy_hash']) {
            return ['decision' => 'deny', 'reason' => 'policy_out_of_sync'];
        }

        $requires2fa = $definition->requires2fa || $definition->riskLevel === 'high';
        if ($requires2fa && ! ($context['two_factor_verified'] ?? false)) {
            $decision = 'require_2fa';
            $reason = '2fa_required';
        }

        if ($device && ($device->risk_score ?? 0) >= 80 && $definition->riskLevel !== 'low') {
            $decision = 'deny';
            $reason = 'risk_too_high';
        }

        return [
            'decision' => $decision,
            'reason' => $reason,
            'requires_2fa' => $decision === 'require_2fa',
        ];
    }
}
