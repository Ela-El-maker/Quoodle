<?php

namespace App\Services\PolicyEngine;

class PolicyEvaluator
{
    public function evaluate(array $context): string
    {
        $risk = $context['command_risk_level'] ?? 'low';
        if ($risk === 'high') {
            return 'require_2fa';
        }
        return 'allow';
    }
}
