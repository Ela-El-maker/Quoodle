<?php

namespace App\Services\Security;

use RuntimeException;

final class Ed25519Signer
{
    public function __construct(
        private readonly string $privateKeyB64,
    ) {
    }

    /**
     * Sign canonical JSON bytes with Ed25519 and return base64 signature.
     */
    public function signCanonicalJson(string $canonicalJson): string
    {
        if (! function_exists('sodium_crypto_sign_detached')) {
            throw new RuntimeException('ext-sodium is required for Ed25519 signing');
        }

        $sk = base64_decode($this->privateKeyB64, true);
        if ($sk === false) {
            throw new RuntimeException('Invalid base64 private key');
        }

        $sig = sodium_crypto_sign_detached($canonicalJson, $sk);
        return base64_encode($sig);
    }

    /**
     * Sign a PHP value by canonicalizing it to JSON first.
     */
    public function signJsonValue(mixed $value): string
    {
        $canonical = Ed25519CanonicalJson::encode($value);
        return $this->signCanonicalJson($canonical);
    }
}
