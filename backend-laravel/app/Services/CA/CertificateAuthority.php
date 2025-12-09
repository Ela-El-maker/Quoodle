<?php

namespace App\Services\CA;

class CertificateAuthority
{
    public function issueDeviceCertificate(array $request): array
    {
        return [
            'status' => 'not_implemented',
            'note' => 'Placeholder per specs; CA issuance is implemented in later phases.',
        ];
    }

    public function chain(): array
    {
        return [];
    }
}
