<?php

namespace App\Services\JWT;

class JWKSManager
{
    public function keySet(): array
    {
        $kid = (string) config('jwt.kid', 'K1');
        $alg = strtoupper((string) config('jwt.alg', 'RS256'));
        if ($alg === 'PS256') {
            $alg = 'RS256';
        }

        $pubPath = (string) config('jwt.public_key_path');
        $pem = @file_get_contents($pubPath);
        if (! is_string($pem) || $pem === '') {
            return ['keys' => []];
        }

        $res = openssl_pkey_get_public($pem);
        if ($res === false) {
            return ['keys' => []];
        }
        $details = openssl_pkey_get_details($res);
        if (! is_array($details) || ($details['type'] ?? null) !== OPENSSL_KEYTYPE_RSA) {
            return ['keys' => []];
        }

        $rsa = $details['rsa'] ?? null;
        if (! is_array($rsa) || empty($rsa['n']) || empty($rsa['e'])) {
            return ['keys' => []];
        }

        $n = $this->b64url($rsa['n']);
        $e = $this->b64url($rsa['e']);

        return [
            'keys' => [
                [
                    'kty' => 'RSA',
                    'use' => 'sig',
                    'kid' => $kid,
                    'alg' => $alg,
                    'n' => $n,
                    'e' => $e,
                ],
            ],
        ];
    }

    private function b64url(string $bin): string
    {
        return rtrim(strtr(base64_encode($bin), '+/', '-_'), '=');
    }
}
