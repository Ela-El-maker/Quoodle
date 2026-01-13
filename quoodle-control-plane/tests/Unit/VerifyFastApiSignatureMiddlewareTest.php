<?php

namespace Tests\Unit;

use App\Http\Middleware\VerifyFastApiSignature;
use App\Services\Security\Ed25519CanonicalJson;
use Illuminate\Http\Request;
use Tests\TestCase;

final class VerifyFastApiSignatureMiddlewareTest extends TestCase
{
    public function testAllowsWhenDisabled(): void
    {
        config()->set('services.fastapi.require_webhook_signature', false);

        $req = Request::create('/api/v1/webhook/command/result', 'POST', [], [], [], [], json_encode(['a' => 1]));
        $mw = new VerifyFastApiSignature();

        $res = $mw->handle($req, fn () => response()->json(['ok' => true]));
        $this->assertSame(200, $res->getStatusCode());
    }

    public function testRejectsMissingHeaderWhenEnabled(): void
    {
        config()->set('services.fastapi.require_webhook_signature', true);
        config()->set('services.fastapi.service_public_key_b64', base64_encode(str_repeat('x', 32)));

        $req = Request::create('/api/v1/webhook/command/result', 'POST', [], [], [], [], json_encode(['a' => 1]));
        $mw = new VerifyFastApiSignature();

        $res = $mw->handle($req, fn () => response()->json(['ok' => true]));
        $this->assertSame(401, $res->getStatusCode());
    }

    public function testAcceptsValidSignatureWhenEnabled(): void
    {
        if (! function_exists('sodium_crypto_sign_keypair')) {
            $this->markTestSkipped('ext-sodium not available');
        }

        $keypair = sodium_crypto_sign_keypair();
        $sk = sodium_crypto_sign_secretkey($keypair);
        $pk = sodium_crypto_sign_publickey($keypair);

        config()->set('services.fastapi.require_webhook_signature', true);
        config()->set('services.fastapi.service_public_key_b64', base64_encode($pk));

        $payload = [
            'timestamp' => '2025-11-22T12:00:10Z',
            'device_id' => 'PC001',
            'command_id' => 'CMD-123',
            'result' => ['status' => 'ok'],
        ];

        $canonical = Ed25519CanonicalJson::encode($payload);
        $sig = sodium_crypto_sign_detached($canonical, $sk);
        $sigB64 = base64_encode($sig);

        $req = Request::create('/api/v1/webhook/command/result', 'POST', [], [], [], [], json_encode($payload));
        $req->headers->set('X-FastAPI-Signature', $sigB64);

        $mw = new VerifyFastApiSignature();
        $res = $mw->handle($req, fn () => response()->json(['ok' => true]));

        $this->assertSame(200, $res->getStatusCode());
    }
}
