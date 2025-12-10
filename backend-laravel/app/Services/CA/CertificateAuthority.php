<?php

namespace App\Services\CA;

class CertificateAuthority
{
    public function issueDeviceCertificate(array $request): array
    {
        $deviceId = $request['device_id'] ?? 'unknown-device';
        $serial = bin2hex(random_bytes(8));
        $certificate = base64_encode("CERT:{$deviceId}:{$serial}");

        return [
            'certificate' => $certificate,
            'serial' => $serial,
            'issued_at' => now()->toIso8601String(),
            'expires_at' => now()->addYear()->toIso8601String(),
        ];
    }

    public function chain(): array
    {
        return [
            'root' => 'root-ca-simulated',
            'intermediate' => 'intermediate-ca-simulated',
        ];
    }
}
