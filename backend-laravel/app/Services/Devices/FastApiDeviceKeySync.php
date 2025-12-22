<?php

namespace App\Services\Devices;

use App\Models\Device;
use App\Services\Security\Ed25519Signer;
use Illuminate\Support\Facades\Http;
use RuntimeException;

final class FastApiDeviceKeySync
{
    /**
     * Push a device's Ed25519 public key to FastAPI registry.
     */
    public function push(Device $device): void
    {
        $base = rtrim(config('services.fastapi.base_url'), '/');
        $url = $base.'/admin/device-keys/'.$device->device_id;

        $skB64 = config('services.fastapi.service_private_key_b64');
        if (! is_string($skB64) || $skB64 === '') {
            throw new RuntimeException('Missing services.fastapi.service_private_key_b64 (LARAVEL_SERVICE_PRIVATE_KEY_B64)');
        }

        $pub = $device->ed25519_pubkey_b64;
        if (! is_string($pub) || $pub === '') {
            // Nothing to sync.
            return;
        }

        $payload = [
            'device_id' => $device->device_id,
            'ed25519_pubkey_b64' => $pub,
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
