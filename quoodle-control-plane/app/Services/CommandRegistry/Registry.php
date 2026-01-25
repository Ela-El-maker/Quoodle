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
            'list_processes' => new CommandDefinition(
                name: 'list_processes',
                riskLevel: 'medium',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: false,
                paramsRules: [
                    'limit' => ['nullable', 'integer', 'min:1', 'max:500'],
                    'user' => ['nullable', 'string', 'max:128'],
                    'name' => ['nullable', 'string', 'max:128'],
                ]
            ),
            'kill_process' => new CommandDefinition(
                name: 'kill_process',
                riskLevel: 'medium',
                minRole: 'user',
                requires2fa: false,
                allowedInQuarantine: false,
                paramsRules: [
                    'pid' => ['required', 'integer', 'min:2'],
                    'signal' => ['nullable', 'integer', 'min:1', 'max:64'],
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
            'reboot_system' => new CommandDefinition(
                name: 'reboot_system',
                riskLevel: 'high',
                minRole: 'user',
                requires2fa: false,
                allowedInQuarantine: false,
                paramsRules: [
                    'delay_seconds' => ['nullable', 'integer', 'min:0', 'max:300'],
                ]
            ),
            'sysinfo' => new CommandDefinition(
                name: 'sysinfo',
                riskLevel: 'low',
                minRole: 'user',
                requires2fa: false,
                allowedInQuarantine: true,
                paramsRules: []
            ),
            'netinfo' => new CommandDefinition(
                name: 'netinfo',
                riskLevel: 'medium',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: false,
                paramsRules: []
            ),
            'list_services' => new CommandDefinition(
                name: 'list_services',
                riskLevel: 'medium',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: false,
                paramsRules: []
            ),
            'start_service' => new CommandDefinition(
                name: 'start_service',
                riskLevel: 'high',
                minRole: 'admin',
                requires2fa: true,
                allowedInQuarantine: false,
                paramsRules: [
                    'unit' => ['required', 'string', 'max:128', 'regex:/^[a-zA-Z0-9\-\._]+$/'],
                ]
            ),
            'stop_service' => new CommandDefinition(
                name: 'stop_service',
                riskLevel: 'high',
                minRole: 'admin',
                requires2fa: true,
                allowedInQuarantine: false,
                paramsRules: [
                    'unit' => ['required', 'string', 'max:128', 'regex:/^[a-zA-Z0-9\-\._]+$/'],
                ]
            ),
            'restart_service' => new CommandDefinition(
                name: 'restart_service',
                riskLevel: 'high',
                minRole: 'admin',
                requires2fa: true,
                allowedInQuarantine: false,
                paramsRules: [
                    'unit' => ['required', 'string', 'max:128', 'regex:/^[a-zA-Z0-9\-\._]+$/'],
                ]
            ),
            'reboot' => new CommandDefinition(
                name: 'reboot',
                riskLevel: 'high',
                minRole: 'admin',
                requires2fa: true,
                allowedInQuarantine: false,
                paramsRules: [
                    'delay_seconds' => ['nullable', 'integer', 'min:0', 'max:300'],
                ]
            ),
            'shutdown' => new CommandDefinition(
                name: 'shutdown',
                riskLevel: 'high',
                minRole: 'admin',
                requires2fa: true,
                allowedInQuarantine: false,
                paramsRules: [
                    'delay_seconds' => ['nullable', 'integer', 'min:0', 'max:300'],
                ]
            ),
            'list_sessions' => new CommandDefinition(
                name: 'list_sessions',
                riskLevel: 'medium',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: false,
                paramsRules: []
            ),
        ];
    }

    public function get(string $name): ?CommandDefinition
    {
        return $this->all()[$name] ?? null;
    }
}
