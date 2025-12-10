<?php

namespace App\Services\PolicyEngine\Rules;

class RateRules
{
    public function underLimit(): bool
    {
        return true;
    }
}
