<?php

namespace App\Services\PolicyEngine\Rules;

class CommandRules
{
    public function allowed(string $method): bool
    {
        return in_array($method, [
            'ping',
            'reboot_device',
            'shutdown_device',
            'collect_system_info',
            'screenshot',
            'list_processes',
            'list_services',
            'list_connections',
            'list_mounts',
            'network_info',
            'get_active_window',
            'list_files',
            'download_file',
            'create_directory',
            'create_file',
            'delete_file',
            'delete_directory',
        ], true);
    }
}
