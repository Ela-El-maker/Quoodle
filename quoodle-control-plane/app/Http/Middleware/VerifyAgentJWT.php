<?php

namespace App\Http\Middleware;

use App\Models\Device;
use Closure;
use Firebase\JWT\JWT;
use Firebase\JWT\Key;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Config;
use Symfony\Component\HttpFoundation\Response;

/**
 * Agent JWT authentication middleware.
 *
 * Validates device-scoped JWTs issued by Laravel for Agent operations.
 */
final class VerifyAgentJWT
{
    public function handle(Request $request, Closure $next): Response
    {
        $authHeader = $request->header('Authorization');

        if (! $authHeader || ! str_starts_with($authHeader, 'Bearer ')) {
            return $this->unauthorized('Missing or invalid Authorization header');
        }

        $token = substr($authHeader, 7);
        if ($token === '') {
            return $this->unauthorized('Empty token');
        }

        try {
            $claims = $this->verifyToken($token);
        } catch (\Firebase\JWT\ExpiredException) {
            return $this->unauthorized('Token expired', 'TOKEN_EXPIRED');
        } catch (\Firebase\JWT\SignatureInvalidException) {
            return $this->unauthorized('Invalid signature', 'SIGNATURE_INVALID');
        } catch (\Firebase\JWT\BeforeValidException) {
            return $this->unauthorized('Token not yet valid', 'TOKEN_NOT_YET_VALID');
        } catch (\Exception $e) {
            return $this->unauthorized('Invalid token: ' . $e->getMessage());
        }

        $expectedIssuer = Config::get('jwt.issuer', 'secure-device-control-system');
        $expectedAudience = Config::get('jwt.audience', 'secure-device-clients');

        if (($claims->iss ?? '') !== $expectedIssuer) {
            return $this->unauthorized('Invalid issuer', 'INVALID_ISSUER');
        }

        if (($claims->aud ?? '') !== $expectedAudience) {
            return $this->unauthorized('Invalid audience', 'INVALID_AUDIENCE');
        }

        $deviceId = $claims->sub ?? null;
        if (! $deviceId) {
            return $this->unauthorized('Missing subject claim', 'INVALID_TOKEN');
        }

        $scope = $claims->scope ?? null;
        if (! in_array($scope, ['agent', 'device'], true)) {
            return $this->unauthorized('Invalid scope', 'INVALID_SCOPE');
        }

        $device = Device::find($deviceId);
        if (! $device) {
            return $this->unauthorized('Device not found', 'DEVICE_NOT_FOUND');
        }

        $request->attributes->set('agent_device_id', $deviceId);
        $request->attributes->set('agent_claims', $claims);

        return $next($request);
    }

    private function verifyToken(string $token): object
    {
        $publicKeyPath = Config::get('jwt.public_key_path');
        if (! $publicKeyPath || ! file_exists($publicKeyPath)) {
            throw new \RuntimeException('JWT public key not configured');
        }

        $publicKey = file_get_contents($publicKeyPath);
        if ($publicKey === false) {
            throw new \RuntimeException('Failed to read JWT public key');
        }

        $algorithm = Config::get('jwt.alg', 'RS256');
        if (strtoupper($algorithm) === 'PS256') {
            $algorithm = 'RS256';
        }

        return JWT::decode($token, new Key($publicKey, $algorithm));
    }

    private function unauthorized(string $message, string $code = 'UNAUTHORIZED'): Response
    {
        return response()->json([
            'message' => 'Unauthorized',
            'error' => $message,
            'code' => $code,
        ], 401);
    }
}
