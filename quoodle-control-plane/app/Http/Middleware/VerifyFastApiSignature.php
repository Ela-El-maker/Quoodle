<?php

namespace App\Http\Middleware;

use App\Services\Security\Ed25519CanonicalJson;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Config;
use Symfony\Component\HttpFoundation\Response;

final class VerifyFastApiSignature
{
    /**
     * Verifies FastAPI→Laravel webhook signatures.
     *
     * Spec:
     * - Header: X-FastAPI-Signature: base64-ed25519
     * - Signature covers canonical JSON of request body
     */
    public function handle(Request $request, Closure $next): Response
    {
        $enabled = (bool) Config::get('services.fastapi.require_webhook_signature', false);
        if (! $enabled) {
            return $next($request);
        }

        $pubB64 = Config::get('services.fastapi.service_public_key_b64');
        if (! is_string($pubB64) || $pubB64 === '') {
            return response()->json(['detail' => 'FASTAPI_SERVICE_PUBLIC_KEY_B64 not configured'], 500);
        }

        $sigB64 = $request->headers->get('X-FastAPI-Signature');
        if (! is_string($sigB64) || $sigB64 === '') {
            return response()->json(['detail' => 'Missing X-FastAPI-Signature'], 401);
        }

        if (! function_exists('sodium_crypto_sign_verify_detached')) {
            return response()->json(['detail' => 'ext-sodium required for signature verification'], 500);
        }

        $raw = $request->getContent();
        try {
            $decoded = json_decode($raw, true, 512, JSON_THROW_ON_ERROR);
        } catch (\Throwable) {
            return response()->json(['detail' => 'Invalid JSON'], 400);
        }

        $canonical = Ed25519CanonicalJson::encode($decoded);

        $sig = base64_decode($sigB64, true);
        $pk = base64_decode($pubB64, true);
        if ($sig === false || $pk === false) {
            return response()->json(['detail' => 'Invalid base64 signature/public key'], 401);
        }

        $ok = sodium_crypto_sign_verify_detached($sig, $canonical, $pk);
        if ($ok !== true) {
            return response()->json(['detail' => 'Invalid signature'], 401);
        }

        return $next($request);
    }
}
