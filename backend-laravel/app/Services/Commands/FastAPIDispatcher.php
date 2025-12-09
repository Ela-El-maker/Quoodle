<?php

namespace App\Services\Commands;

use App\Models\Command;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;

class FastAPIDispatcher
{
    public function dispatch(Command $command): array
    {
        $base = rtrim(config('services.fastapi.base_url'), '/');
        $url = $base.'/command/dispatch';

        $payload = [
            'command_id' => $command->id,
            'device_id' => $command->device_id,
            'trace_id' => $command->trace_id,
            'seq' => 1,
            'method' => $command->method,
            'params' => $command->params ?? [],
            'sensitive' => $command->sensitive,
            'envelope' => [
                'header' => [
                    'version' => '1.1',
                    'timestamp' => now()->toIso8601String(),
                    'ttl_seconds' => 300,
                    'priority' => 'normal',
                    'requires_ack' => true,
                    'long_running' => false,
                ],
                'body' => [
                    'method' => $command->method,
                    'params' => $command->params ?? [],
                    'sensitive' => $command->sensitive,
                ],
                'meta' => [
                    'origin_user_id' => 'user-unknown',
                    'enc' => 'none',
                    'enc_key_id' => null,
                    'policy_version' => 'policy-placeholder',
                    'device_id' => $command->device_id,
                ],
                'sig' => 'laravel-sig-placeholder',
            ],
        ];

        $response = Http::acceptJson()->post($url, $payload);

        if (! $response->ok()) {
            return [
                'status' => 'backpressure',
                'reason' => 'fastapi_unreachable',
            ];
        }

        return $response->json();
    }
}
