<?php

namespace App\Services\Commands;

use App\Models\Command;
use App\Services\Audit\AuditArchiveWriter;
use App\Services\Security\Ed25519CanonicalJson;
use App\Services\Security\Ed25519Signer;
use App\Services\Security\MonotonicCounter;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Str;
use RuntimeException;

class FastAPIDispatcher
{
    public function __construct(
        private readonly MonotonicCounter $counter,
        private readonly AuditArchiveWriter $auditArchive,
    ) {
    }

    public function dispatch(Command $command, array $policyDecision, array $compliance): array
    {
        $base = rtrim(config('services.fastapi.base_url'), '/');
        $url = $base.'/command/dispatch';

        $serviceSkB64 = config('services.fastapi.service_private_key_b64');
        if (! is_string($serviceSkB64) || $serviceSkB64 === '') {
            throw new RuntimeException('Missing services.fastapi.service_private_key_b64 (LARAVEL_SERVICE_PRIVATE_KEY_B64)');
        }
        $signer = new Ed25519Signer($serviceSkB64);

        $payload = [
            'command_id' => $command->id,
            'device_id' => $command->device_id,
            'trace_id' => $command->trace_id,
            'seq' => $this->counter->next('fastapi_dispatch'),
            'method' => $command->method,
            'params' => $command->params ?? [],
            'sensitive' => $command->sensitive,
            'policy' => $policyDecision,
            'compliance' => $compliance,
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
                'sig' => null,
            ],
        ];

        // Per spec, envelope.sig is a Laravel signature. Sign envelope without the sig field.
        $payload['envelope']['sig'] = $signer->signJsonValue(Ed25519CanonicalJson::stripSig($payload['envelope']));

        // Transport-level request signature header: sign full request body.
        $requestSig = $signer->signJsonValue($payload);

        // Persist audit data on the command record.
        $command->update([
            'server_seq' => $payload['seq'],
            'envelope' => $payload['envelope'],
            'envelope_sig' => $payload['envelope']['sig'],
            'request_sig' => $requestSig,
        ]);

        $this->auditArchive->appendCommandEnvelope($command);

        $response = Http::acceptJson()
            ->withHeaders([
                'X-Laravel-Signature' => $requestSig,
            ])
            ->timeout(5)
            ->retry(1, 200)
            ->post($url, $payload);

        if (! $response->ok()) {
            return [
                'status' => 'backpressure',
                'reason' => 'fastapi_unreachable',
            ];
        }

        return $response->json();
    }
}
