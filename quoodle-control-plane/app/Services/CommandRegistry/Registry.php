<?php

namespace App\Services\CommandRegistry;

class Registry
{
    public function all(): array
    {
        $relativePath = ['required', 'string', 'max:512', 'regex:/^(?!\/)(?!.*\.{2})[\w\-\.\/ ]+$/'];
        $optionalPath = ['nullable', 'string', 'max:512', 'regex:/^(?!\/)(?!.*\.{2})[\w\-\.\/ ]+$/'];
        $filesystemPath = ['required', 'string', 'max:1024'];
        $confirmRequired = ['required', 'accepted'];

        return [
            // Device Control
            'lock_screen' => new CommandDefinition(
                name: 'lock_screen',
                riskLevel: 'low',
                minRole: 'user',
                requires2fa: false,
                allowedInQuarantine: true,
                paramsRules: []
            ),
            'logout_user' => new CommandDefinition(
                name: 'logout_user',
                riskLevel: 'medium',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: false,
                paramsRules: []
            ),
            'reboot_device' => new CommandDefinition(
                name: 'reboot_device',
                riskLevel: 'high',
                minRole: 'admin',
                requires2fa: true,
                allowedInQuarantine: false,
                paramsRules: [
                    'delay_seconds' => ['nullable', 'integer', 'min:0', 'max:300'],
                ]
            ),
            'shutdown_device' => new CommandDefinition(
                name: 'shutdown_device',
                riskLevel: 'high',
                minRole: 'admin',
                requires2fa: true,
                allowedInQuarantine: false,
                paramsRules: [
                    'delay_seconds' => ['nullable', 'integer', 'min:0', 'max:300'],
                    'force' => ['nullable', 'boolean'],
                ]
            ),
            'disable_input' => new CommandDefinition(
                name: 'disable_input',
                riskLevel: 'high',
                minRole: 'admin',
                requires2fa: true,
                allowedInQuarantine: false,
                paramsRules: [
                    'duration_seconds' => ['required', 'integer', 'min:5', 'max:300'],
                    'scope' => ['nullable', 'string', 'in:all,mouse,keyboard'],
                ]
            ),
            'enable_input' => new CommandDefinition(
                name: 'enable_input',
                riskLevel: 'low',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: true,
                paramsRules: [
                    'scope' => ['nullable', 'string', 'in:all,mouse,keyboard'],
                ]
            ),
            'set_wallpaper' => new CommandDefinition(
                name: 'set_wallpaper',
                riskLevel: 'low',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: false,
                paramsRules: [
                    'message' => ['nullable', 'string', 'max:200'],
                    'image_url' => ['nullable', 'string', 'max:2048'],
                ]
            ),
            'show_message' => new CommandDefinition(
                name: 'show_message',
                riskLevel: 'low',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: true,
                paramsRules: [
                    'message' => ['required', 'string', 'max:400'],
                    'severity' => ['nullable', 'string', 'in:info,warning,critical'],
                    'timeout_seconds' => ['nullable', 'integer', 'min:1', 'max:120'],
                    'blocking' => ['nullable', 'boolean'],
                ]
            ),

            // Visibility & Reconnaissance
            'collect_system_info' => new CommandDefinition(
                name: 'collect_system_info',
                riskLevel: 'low',
                minRole: 'user',
                requires2fa: false,
                allowedInQuarantine: true,
                paramsRules: []
            ),
            'list_processes' => new CommandDefinition(
                name: 'list_processes',
                riskLevel: 'medium',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: false,
                paramsRules: [
                    'limit' => ['nullable', 'integer', 'min:1', 'max:1000'],
                    'user' => ['nullable', 'string', 'max:128'],
                    'name' => ['nullable', 'string', 'max:128'],
                ]
            ),
            'get_users' => new CommandDefinition(
                name: 'get_users',
                riskLevel: 'medium',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: false,
                paramsRules: [
                    'limit' => ['nullable', 'integer', 'min:1', 'max:200'],
                ]
            ),
            'get_sessions' => new CommandDefinition(
                name: 'get_sessions',
                riskLevel: 'medium',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: false,
                paramsRules: [
                    'limit' => ['nullable', 'integer', 'min:1', 'max:200'],
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
            'list_services' => new CommandDefinition(
                name: 'list_services',
                riskLevel: 'medium',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: false,
                paramsRules: []
            ),
            'network_info' => new CommandDefinition(
                name: 'network_info',
                riskLevel: 'medium',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: false,
                paramsRules: [
                    'limit' => ['nullable', 'integer', 'min:1', 'max:1000'],
                    'include_wifi' => ['nullable', 'boolean'],
                    'include_routes' => ['nullable', 'boolean'],
                    'include_vpn_signals' => ['nullable', 'boolean'],
                ]
            ),
            'netinfo' => new CommandDefinition(
                name: 'netinfo',
                riskLevel: 'medium',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: false,
                paramsRules: [
                    'limit' => ['nullable', 'integer', 'min:1', 'max:1000'],
                    'include_wifi' => ['nullable', 'boolean'],
                    'include_routes' => ['nullable', 'boolean'],
                    'include_vpn_signals' => ['nullable', 'boolean'],
                ]
            ),
            'list_mounts' => new CommandDefinition(
                name: 'list_mounts',
                riskLevel: 'medium',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: false,
                paramsRules: []
            ),
            'get_env_fingerprint' => new CommandDefinition(
                name: 'get_env_fingerprint',
                riskLevel: 'medium',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: false,
                paramsRules: []
            ),

            // File System Access (lab-scoped)
            'list_files' => new CommandDefinition(
                name: 'list_files',
                riskLevel: 'medium',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: false,
                paramsRules: [
                    'path' => ['nullable', 'string', 'max:1024'],
                    'recursive' => ['nullable', 'boolean'],
                    'max_depth' => ['nullable', 'integer', 'min:1', 'max:16'],
                    'limit' => ['nullable', 'integer', 'min:1', 'max:1000'],
                    'include_hidden' => ['nullable', 'boolean'],
                    'include_system' => ['nullable', 'boolean'],
                    'follow_symlinks' => ['nullable', 'boolean'],
                ]
            ),
            'stat_file' => new CommandDefinition(
                name: 'stat_file',
                riskLevel: 'medium',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: false,
                paramsRules: [
                    'path' => $relativePath,
                ]
            ),
            'read_file' => new CommandDefinition(
                name: 'read_file',
                riskLevel: 'high',
                minRole: 'analyst',
                requires2fa: true,
                allowedInQuarantine: false,
                paramsRules: [
                    'path' => $relativePath,
                    'max_bytes' => ['nullable', 'integer', 'min:1', 'max:1048576'],
                    'encoding' => ['nullable', 'string', 'in:utf8,base64'],
                ]
            ),
            'search_files' => new CommandDefinition(
                name: 'search_files',
                riskLevel: 'high',
                minRole: 'analyst',
                requires2fa: true,
                allowedInQuarantine: false,
                paramsRules: [
                    'path' => $relativePath,
                    'pattern' => ['required', 'string', 'max:128'],
                    'regex' => ['nullable', 'boolean'],
                    'limit' => ['nullable', 'integer', 'min:1', 'max:200'],
                ]
            ),
            'hash_file' => new CommandDefinition(
                name: 'hash_file',
                riskLevel: 'low',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: false,
                paramsRules: [
                    'path' => $relativePath,
                    'algo' => ['nullable', 'string', 'in:sha256,sha1,md5'],
                ]
            ),
            'download_file' => new CommandDefinition(
                name: 'download_file',
                riskLevel: 'medium',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: false,
                paramsRules: [
                    'path' => $filesystemPath,
                    'max_bytes' => ['nullable', 'integer', 'min:1', 'max:5242880'],
                ]
            ),
            'create_directory' => new CommandDefinition(
                name: 'create_directory',
                riskLevel: 'high',
                minRole: 'admin',
                requires2fa: true,
                allowedInQuarantine: false,
                paramsRules: [
                    'path' => $filesystemPath,
                    'recursive' => ['nullable', 'boolean'],
                ]
            ),
            'create_file' => new CommandDefinition(
                name: 'create_file',
                riskLevel: 'high',
                minRole: 'admin',
                requires2fa: true,
                allowedInQuarantine: false,
                paramsRules: [
                    'path' => $filesystemPath,
                    'overwrite' => ['nullable', 'boolean'],
                ]
            ),
            'upload_file' => new CommandDefinition(
                name: 'upload_file',
                riskLevel: 'high',
                minRole: 'admin',
                requires2fa: true,
                allowedInQuarantine: false,
                paramsRules: [
                    'artifact_id' => ['required', 'string', 'max:128'],
                    'destination' => $relativePath,
                    'overwrite' => ['nullable', 'boolean'],
                ]
            ),
            'delete_file' => new CommandDefinition(
                name: 'delete_file',
                riskLevel: 'high',
                minRole: 'admin',
                requires2fa: true,
                allowedInQuarantine: false,
                paramsRules: [
                    'path' => $filesystemPath,
                    'confirm' => $confirmRequired,
                ]
            ),
            'delete_directory' => new CommandDefinition(
                name: 'delete_directory',
                riskLevel: 'high',
                minRole: 'admin',
                requires2fa: true,
                allowedInQuarantine: false,
                paramsRules: [
                    'path' => $filesystemPath,
                    'confirm' => $confirmRequired,
                ]
            ),
            'move_file' => new CommandDefinition(
                name: 'move_file',
                riskLevel: 'high',
                minRole: 'admin',
                requires2fa: true,
                allowedInQuarantine: false,
                paramsRules: [
                    'src' => $relativePath,
                    'dest' => $relativePath,
                    'overwrite' => ['nullable', 'boolean'],
                ]
            ),

            // Screen & User Context
            'screenshot' => new CommandDefinition(
                name: 'screenshot',
                riskLevel: 'medium',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: false,
                paramsRules: [
                    'resolution' => ['nullable', 'string', 'in:original,1080p,720p'],
                    'format' => ['nullable', 'string', 'in:png,jpeg'],
                ]
            ),
            'get_active_window' => new CommandDefinition(
                name: 'get_active_window',
                riskLevel: 'medium',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: false,
                paramsRules: []
            ),
            'get_idle_time' => new CommandDefinition(
                name: 'get_idle_time',
                riskLevel: 'medium',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: false,
                paramsRules: []
            ),
            'lock_and_capture' => new CommandDefinition(
                name: 'lock_and_capture',
                riskLevel: 'high',
                minRole: 'admin',
                requires2fa: true,
                allowedInQuarantine: false,
                paramsRules: [
                    'message' => ['nullable', 'string', 'max:200'],
                    'timeout_seconds' => ['nullable', 'integer', 'min:1', 'max:120'],
                ]
            ),

            // Process Control
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
            'kill_process_tree' => new CommandDefinition(
                name: 'kill_process_tree',
                riskLevel: 'high',
                minRole: 'admin',
                requires2fa: true,
                allowedInQuarantine: false,
                paramsRules: [
                    'pid' => ['required', 'integer', 'min:2'],
                ]
            ),
            'pause_process' => new CommandDefinition(
                name: 'pause_process',
                riskLevel: 'high',
                minRole: 'admin',
                requires2fa: true,
                allowedInQuarantine: false,
                paramsRules: [
                    'pid' => ['required', 'integer', 'min:2'],
                ]
            ),
            'resume_process' => new CommandDefinition(
                name: 'resume_process',
                riskLevel: 'medium',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: false,
                paramsRules: [
                    'pid' => ['required', 'integer', 'min:2'],
                ]
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

            // Network Manipulation
            'disconnect_network' => new CommandDefinition(
                name: 'disconnect_network',
                riskLevel: 'high',
                minRole: 'admin',
                requires2fa: true,
                allowedInQuarantine: false,
                paramsRules: [
                    'confirm' => $confirmRequired,
                    'duration_seconds' => ['nullable', 'integer', 'min:1', 'max:600'],
                ]
            ),
            'reconnect_network' => new CommandDefinition(
                name: 'reconnect_network',
                riskLevel: 'low',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: true,
                paramsRules: []
            ),
            'list_connections' => new CommandDefinition(
                name: 'list_connections',
                riskLevel: 'medium',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: false,
                paramsRules: [
                    'limit' => ['nullable', 'integer', 'min:1', 'max:1000'],
                    'include_ipv6' => ['nullable', 'boolean'],
                    'include_udp' => ['nullable', 'boolean'],
                    'include_process_path' => ['nullable', 'boolean'],
                ]
            ),
            'block_outbound' => new CommandDefinition(
                name: 'block_outbound',
                riskLevel: 'high',
                minRole: 'admin',
                requires2fa: true,
                allowedInQuarantine: false,
                paramsRules: [
                    'duration_seconds' => ['nullable', 'integer', 'min:1', 'max:3600'],
                ]
            ),
            'allow_outbound' => new CommandDefinition(
                name: 'allow_outbound',
                riskLevel: 'low',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: true,
                paramsRules: []
            ),

            // Identity & Trust
            'rotate_agent_keys' => new CommandDefinition(
                name: 'rotate_agent_keys',
                riskLevel: 'high',
                minRole: 'admin',
                requires2fa: true,
                allowedInQuarantine: false,
                paramsRules: [
                    'reason' => ['nullable', 'string', 'max:200'],
                ]
            ),
            'revoke_device' => new CommandDefinition(
                name: 'revoke_device',
                riskLevel: 'high',
                minRole: 'admin',
                requires2fa: true,
                allowedInQuarantine: false,
                paramsRules: [
                    'reason' => ['nullable', 'string', 'max:200'],
                ]
            ),
            'force_repair' => new CommandDefinition(
                name: 'force_repair',
                riskLevel: 'medium',
                minRole: 'admin',
                requires2fa: false,
                allowedInQuarantine: true,
                paramsRules: [
                    'component' => ['nullable', 'string', 'max:200'],
                ]
            ),
            'invalidate_sessions' => new CommandDefinition(
                name: 'invalidate_sessions',
                riskLevel: 'high',
                minRole: 'admin',
                requires2fa: true,
                allowedInQuarantine: false,
                paramsRules: [
                    'scope' => ['nullable', 'string', 'in:device,user,all'],
                ]
            ),
            're_attest' => new CommandDefinition(
                name: 're_attest',
                riskLevel: 'medium',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: true,
                paramsRules: [
                    'include_tpm' => ['nullable', 'boolean'],
                ]
            ),

            // Compliance & Policy Simulation
            'attest_device' => new CommandDefinition(
                name: 'attest_device',
                riskLevel: 'medium',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: true,
                paramsRules: [
                    'include_tpm' => ['nullable', 'boolean'],
                ]
            ),
            'fail_attestation' => new CommandDefinition(
                name: 'fail_attestation',
                riskLevel: 'high',
                minRole: 'admin',
                requires2fa: true,
                allowedInQuarantine: true,
                paramsRules: [
                    'reason' => ['nullable', 'string', 'max:200'],
                ]
            ),
            'enter_quarantine' => new CommandDefinition(
                name: 'enter_quarantine',
                riskLevel: 'high',
                minRole: 'admin',
                requires2fa: true,
                allowedInQuarantine: true,
                paramsRules: [
                    'reason' => ['nullable', 'string', 'max:200'],
                ]
            ),
            'exit_quarantine' => new CommandDefinition(
                name: 'exit_quarantine',
                riskLevel: 'medium',
                minRole: 'admin',
                requires2fa: false,
                allowedInQuarantine: true,
                paramsRules: [
                    'reason' => ['nullable', 'string', 'max:200'],
                ]
            ),
            'policy_probe' => new CommandDefinition(
                name: 'policy_probe',
                riskLevel: 'medium',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: true,
                paramsRules: [
                    'command' => ['nullable', 'string', 'max:128'],
                ]
            ),

            // Audit, Evidence & Forensics
            'get_command_log' => new CommandDefinition(
                name: 'get_command_log',
                riskLevel: 'low',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: true,
                paramsRules: [
                    'limit' => ['nullable', 'integer', 'min:1', 'max:500'],
                ]
            ),
            'get_audit_trail' => new CommandDefinition(
                name: 'get_audit_trail',
                riskLevel: 'low',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: true,
                paramsRules: [
                    'limit' => ['nullable', 'integer', 'min:1', 'max:500'],
                ]
            ),
            'export_artifacts' => new CommandDefinition(
                name: 'export_artifacts',
                riskLevel: 'medium',
                minRole: 'analyst',
                requires2fa: false,
                allowedInQuarantine: true,
                paramsRules: [
                    'since' => ['nullable', 'string', 'max:64'],
                ]
            ),
            'verify_signature' => new CommandDefinition(
                name: 'verify_signature',
                riskLevel: 'low',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: true,
                paramsRules: [
                    'artifact_id' => ['nullable', 'string', 'max:128'],
                    'signature' => ['nullable', 'string', 'max:2048'],
                    'public_key' => ['nullable', 'string', 'max:2048'],
                ]
            ),
            'replay_request' => new CommandDefinition(
                name: 'replay_request',
                riskLevel: 'medium',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: true,
                paramsRules: [
                    'command_id' => ['required', 'string', 'max:128'],
                ]
            ),

            // Recovery & Safety
            'panic_disable_agent' => new CommandDefinition(
                name: 'panic_disable_agent',
                riskLevel: 'high',
                minRole: 'admin',
                requires2fa: true,
                allowedInQuarantine: true,
                paramsRules: [
                    'duration_seconds' => ['nullable', 'integer', 'min:1', 'max:3600'],
                ]
            ),
            'revoke_all_keys' => new CommandDefinition(
                name: 'revoke_all_keys',
                riskLevel: 'high',
                minRole: 'admin',
                requires2fa: true,
                allowedInQuarantine: true,
                paramsRules: [
                    'reason' => ['nullable', 'string', 'max:200'],
                ]
            ),
            'restore_defaults' => new CommandDefinition(
                name: 'restore_defaults',
                riskLevel: 'high',
                minRole: 'admin',
                requires2fa: true,
                allowedInQuarantine: true,
                paramsRules: [
                    'scope' => ['nullable', 'string', 'max:128'],
                ]
            ),
            'unlock_all' => new CommandDefinition(
                name: 'unlock_all',
                riskLevel: 'low',
                minRole: 'operator',
                requires2fa: false,
                allowedInQuarantine: true,
                paramsRules: []
            ),
            'health_check' => new CommandDefinition(
                name: 'health_check',
                riskLevel: 'low',
                minRole: 'user',
                requires2fa: false,
                allowedInQuarantine: true,
                paramsRules: []
            ),

            // Existing operational commands
            'ping' => new CommandDefinition(
                name: 'ping',
                riskLevel: 'low',
                minRole: 'user',
                requires2fa: false,
                allowedInQuarantine: true,
                paramsRules: []
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
        ];
    }

    public function get(string $name): ?CommandDefinition
    {
        return $this->all()[$name] ?? null;
    }
}
