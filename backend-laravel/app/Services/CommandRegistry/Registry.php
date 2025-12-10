<?php

namespace App\Services\CommandRegistry;

class Registry
{
    /**
     * @return array<string, CommandDefinition>
     */
    public function all(): array
    {
        return [
            'lock_screen' => new CommandDefinition('lock_screen'),
            'ping' => new CommandDefinition('ping'),
        ];
    }
}
