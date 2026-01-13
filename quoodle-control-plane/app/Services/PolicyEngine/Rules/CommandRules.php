<?php

namespace App\Services\PolicyEngine\Rules;

class CommandRules
{
    public function allowed(string $method): bool
    {
        return in_array($method, ['lock_screen', 'ping', 'reboot', 'shutdown'], true);
    }
}
