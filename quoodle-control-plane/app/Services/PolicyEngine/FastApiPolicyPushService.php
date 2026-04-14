<?php

namespace App\Services\PolicyEngine;

use App\Services\Security\Ed25519Signer;
use Illuminate\Support\Facades\Http;
use RuntimeException;

final class FastApiPolicyPushService
{
    /**
     * Push the current app-lock policy bundle to FastAPI for fan-out to online agents.
     *
     * @return array<string, mixed>
     */
    public function pushAppLockPolicy(array $appLockBundle, ?array $targetDeviceIds = null): array
    {
        $base = rtrim((string) config('services.fastapi.base_url'), '/');
        $url = $base.'/policy/push';

        $skB64 = config('services.fastapi.service_private_key_b64');
        if (! is_string($skB64) || $skB64 === '') {
            throw new RuntimeException('Missing services.fastapi.service_private_key_b64 (LARAVEL_SERVICE_PRIVATE_KEY_B64)');
        }

        $policyVersion = (string) config('policy.version');
        $policyHash = (string) config('policy.master_hash');
        if ($policyVersion === '' || $policyHash === '') {
            throw new RuntimeException('POLICY_VERSION and POLICY_HASH must be configured');
        }

        $payload = [
            'policy_version' => $policyVersion,
            'policy_hash' => $policyHash,
            'policy_url' => 'control-plane://policy/app-lock',
            'signed_at' => now()->toIso8601String(),
            'signature' => '',
            'app_lock' => $appLockBundle,
            'target_device_ids' => $targetDeviceIds,
        ];

        $signer = new Ed25519Signer($skB64);
        $unsignedPayload = $payload;
        $unsignedPayload['signature'] = '';
        $payload['signature'] = $signer->signJsonValue($unsignedPayload);
        $requestSig = $signer->signJsonValue($payload);

        $response = Http::acceptJson()
            ->withHeaders(['X-Laravel-Signature' => $requestSig])
            ->timeout(5)
            ->retry(1, 200)
            ->post($url, $payload);

        if (! $response->ok()) {
            $body = $response->body();
            throw new RuntimeException('FastAPI policy push failed ['.$response->status().']: '.$body);
        }

        return $response->json();
    }
}
