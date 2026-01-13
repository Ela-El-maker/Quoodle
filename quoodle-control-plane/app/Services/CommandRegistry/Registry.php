<?php

namespace App\Services\CommandRegistry;

class Registry
{
    public function all(): array
    {
        return [
            'lock_screen' => new CommandDefinition(
                name: 'lock_screen',
                riskLevel: 'low',
                minRole: 'user',
                requires2fa: false,
                allowedInQuarantine: true,
                paramsRules: []
            ),
            'ping' => new CommandDefinition(
                name: 'ping',
                riskLevel: 'low',
                minRole: 'user',
                requires2fa: false,
                allowedInQuarantine: true,
                paramsRules: []
            ),
            'screenshot' => new CommandDefinition(
                name: 'screenshot',
                riskLevel: 'high',
                minRole: 'analyst',
                requires2fa: true,
                allowedInQuarantine: false,
                paramsRules: [
                    'resolution' => ['nullable', 'string', 'in:original,1080p,720p'],
                ]
            ),
            'collect_logs' => new CommandDefinition(
                name: 'collect_logs',
                riskLevel: 'medium',
                minRole: 'analyst',
                requires2fa: false,
                allowedInQuarantine: false,
                paramsRules: [
                    'lines' => ['nullable', 'integer', 'min:10', 'max:5000'],
                ]
            ),
            'update_agent' => new CommandDefinition(
                name: 'update_agent',
                riskLevel: 'high',
                minRole: 'admin',
                requires2fa: true,
                allowedInQuarantine: false,
                paramsRules: [
                    'version' => ['required', 'string', 'max:50'],
                    'reboot_after' => ['boolean'],
                ]
            ),
            'rotate_keys' => new CommandDefinition(
                name: 'rotate_keys',
                riskLevel: 'high',
                minRole: 'admin',
                requires2fa: true,
                allowedInQuarantine: false,
                paramsRules: [
                    'reason' => ['required', 'string', 'max:255'],
                ]
            ),
        ];
    }

    public function get(string $name): ?CommandDefinition
    {
        return $this->all()[$name] ?? null;
    }
}
