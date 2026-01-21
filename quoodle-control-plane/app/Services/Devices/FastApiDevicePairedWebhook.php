<?php

namespace App\Services\Devices;

use App\Models\Device;
use App\Services\Security\Ed25519Signer;
use Illuminate\Support\Facades\Http;
use RuntimeException;

final class FastApiDevicePairedWebhook
{
    /**
     * Notify FastAPI that a device has been paired and provide key material.
     */
    public function notify(Device $device, string $agentJwt, string $agentJwtExpiresAt): void
    {
        $base = rtrim((string) config('services.fastapi.base_url'), '/');
        $url = $base.'/webhook/device/paired';

        $skB64 = config('services.fastapi.service_private_key_b64');
        if (! is_string($skB64) || $skB64 === '') {
            throw new RuntimeException('Missing services.fastapi.service_private_key_b64 (LARAVEL_SERVICE_PRIVATE_KEY_B64)');
        }

        $policyHash = (string) config('policy.master_hash');
        $policyVersion = (string) config('policy.version');

        $payload = [
            'device_id' => $device->device_id,
            'device_name' => $device->device_name,
            'user_id' => (string) $device->user_id,
            'ed25519_pubkey_b64' => $device->ed25519_pubkey_b64,
            'policy_hash' => $policyHash,
            'policy_version' => $policyVersion,
            'paired_at' => now()->toIso8601String(),
            'agent_jwt' => $agentJwt,
            'agent_jwt_expires_at' => $agentJwtExpiresAt,
        ];

        $signer = new Ed25519Signer($skB64);
        $sig = $signer->signJsonValue($payload);

        Http::acceptJson()
            ->withHeaders(['X-Laravel-Signature' => $sig])
            ->timeout(5)
            ->retry(1, 200)
            ->post($url, $payload)
            ->throw();
    }
}
