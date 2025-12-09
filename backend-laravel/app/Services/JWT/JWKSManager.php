<?php

namespace App\Services\JWT;

use RuntimeException;

class JWKSManager
{
    public function __construct(private readonly JWTSigner $signer)
    {
    }

    public function keySet(): array
    {
        $resource = openssl_pkey_get_public($this->signer->publicKey());

        if ($resource === false) {
            throw new RuntimeException('Invalid JWT public key material.');
        }

        $details = openssl_pkey_get_details($resource);

        if ($details === false || ! isset($details['rsa'])) {
            throw new RuntimeException('Unable to extract RSA components for JWKS.');
        }

        return [
            'keys' => [
                [
                    'kty' => 'RSA',
                    'kid' => $this->signer->kid(),
                    'use' => 'sig',
                    'alg' => $this->signer->algorithm(),
                    'n' => $this->base64UrlEncode($details['rsa']['n']),
                    'e' => $this->base64UrlEncode($details['rsa']['e']),
                ],
            ],
        ];
    }

    private function base64UrlEncode(string $value): string
    {
        return rtrim(strtr(base64_encode($value), '+/', '-_'), '=');
    }
}
