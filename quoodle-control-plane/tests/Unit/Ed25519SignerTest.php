<?php

namespace Tests\Unit;

use App\Services\Security\Ed25519CanonicalJson;
use App\Services\Security\Ed25519Signer;
use PHPUnit\Framework\Attributes\CoversClass;
use PHPUnit\Framework\TestCase;

#[CoversClass(Ed25519CanonicalJson::class)]
#[CoversClass(Ed25519Signer::class)]
final class Ed25519SignerTest extends TestCase
{
    public function testCanonicalJsonSortsKeysRecursively(): void
    {
        $value = [
            'b' => 2,
            'a' => [
                'd' => 4,
                'c' => 3,
            ],
        ];

        $json = Ed25519CanonicalJson::encode($value);
        $this->assertSame('{"a":{"c":3,"d":4},"b":2}', $json);
    }

    public function testStripSigRemovesSigKeys(): void
    {
        $value = [
            'sig' => 'x',
            'a' => [
                'sig' => 'y',
                'b' => 1,
            ],
        ];

        $stripped = Ed25519CanonicalJson::stripSig($value);
        $this->assertSame(['a' => ['b' => 1]], $stripped);
    }

    public function testEd25519SignatureIsVerifiable(): void
    {
        if (! function_exists('sodium_crypto_sign_keypair')) {
            $this->markTestSkipped('ext-sodium not available');
        }

        $keypair = sodium_crypto_sign_keypair();
        $sk = sodium_crypto_sign_secretkey($keypair);
        $pk = sodium_crypto_sign_publickey($keypair);

        $signer = new Ed25519Signer(base64_encode($sk));

        $payload = [
            'command_id' => 'CMD-123',
            'device_id' => 'PC001',
            'seq' => 1,
            'envelope' => [
                'header' => ['timestamp' => '2025-11-22T12:00:00Z'],
                'body' => ['method' => 'ping', 'params' => [], 'sensitive' => false],
                'meta' => ['enc' => 'none'],
            ],
        ];

        $canonical = Ed25519CanonicalJson::encode($payload);
        $sigB64 = $signer->signCanonicalJson($canonical);
        $sig = base64_decode($sigB64, true);

        $this->assertNotFalse($sig);
        $this->assertSame(1, sodium_crypto_sign_verify_detached($sig, $canonical, $pk));
    }
}
