<?php

namespace App\Services\PolicyEngine\Rules;

class TimeRules
{
    public function withinWindow(): bool
    {
        return true;
    }
}
