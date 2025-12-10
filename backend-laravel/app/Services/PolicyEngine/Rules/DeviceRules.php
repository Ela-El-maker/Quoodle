<?php

namespace App\Services\PolicyEngine\Rules;

class DeviceRules
{
    public function lifecycleAllows(string $state): bool
    {
        return $state !== 'quarantine';
    }
}
