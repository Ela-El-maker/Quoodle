<?php

namespace App\Services\Compliance;

class ComplianceChecker
{
    public function check(array $context): string
    {
        if (($context['attestation_status'] ?? '') !== 'pass') {
            return 'non_compliant';
        }
        if (($context['last_update_state'] ?? '') === 'failed') {
            return 'non_compliant';
        }
        return 'compliant';
    }
}
