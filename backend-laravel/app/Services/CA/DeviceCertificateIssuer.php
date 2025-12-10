<?php

namespace App\Services\CA;

class DeviceCertificateIssuer
{
    public function issue(string $deviceId, string $csr): array
    {
        $serial = bin2hex(random_bytes(8));
        return [
            'certificate' => base64_encode("CERT:{$deviceId}:{$csr}:{$serial}"),
            'csr' => $csr,
            'serial' => $serial,
            'issued_at' => now()->toIso8601String(),
            'expires_at' => now()->addYear()->toIso8601String(),
        ];
    }
}
