<?php

namespace App\Services\Commands;

use App\Services\CommandRegistry\Registry;

class RuntimeCapabilities
{
    /**
     * Methods currently implemented end-to-end in the kernel pipeline.
     */
    private const RUNTIME_SUPPORTED_METHODS = [
        'ping',
        'lock_screen',
        'logout_user',
        'reboot_device',
        'shutdown_device',
        'collect_system_info',
        'screenshot',
        'list_processes',
        'kill_process',
        
        'list_services',
        'list_connections',
        'list_mounts',
        'network_info',
        'get_active_window',
        'list_files',
        'download_file',
    ];

    public function __construct(private readonly Registry $registry)
    {
    }

    /**
     * @return string[]
     */
    public function canonicalMethods(): array
    {
        $methods = array_keys($this->registry->all());
        sort($methods);

        return $methods;
    }

    /**
     * @return string[]
     */
    public function runtimeSupportedMethods(): array
    {
        return self::RUNTIME_SUPPORTED_METHODS;
    }

    public function isRuntimeSupported(string $method): bool
    {
        return in_array($method, self::RUNTIME_SUPPORTED_METHODS, true);
    }

    /**
     * @return array<string,string>
     */
    public function rejectionReasonsByMethod(): array
    {
        $reasons = [];
        foreach ($this->canonicalMethods() as $method) {
            if (! $this->isRuntimeSupported($method)) {
                $reasons[$method] = 'not_supported_runtime';
            }
        }

        return $reasons;
    }
}
