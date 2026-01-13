<?php

namespace App\Http\Middleware;

use App\Models\AuthToken;
use App\Models\User;
use Closure;
use Firebase\JWT\JWT;
use Firebase\JWT\Key;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Config;
use Symfony\Component\HttpFoundation\Response;

/**
 * JWT Authentication Middleware
 *
 * Validates Bearer tokens issued by this system and sets the authenticated user.
 *
 * Token format: Authorization: Bearer <jwt>
 *
 * JWT Claims validated:
 *   - exp: Token expiration time
 *   - iss: Issuer (must match config)
 *   - aud: Audience (must match config)
 *   - sub: User ID
 *   - session_id: Session identifier (checked for revocation)
 */
final class VerifyJWT
{
    /**
     * Handle an incoming request.
     */
    public function handle(Request $request, Closure $next): Response
    {
        $authHeader = $request->header('Authorization');

        if (!$authHeader || !str_starts_with($authHeader, 'Bearer ')) {
            return $this->unauthorized('Missing or invalid Authorization header');
        }

        $token = substr($authHeader, 7);

        if (empty($token)) {
            return $this->unauthorized('Empty token');
        }

        try {
            $claims = $this->verifyToken($token);
        } catch (\Firebase\JWT\ExpiredException $e) {
            return $this->unauthorized('Token expired', 'TOKEN_EXPIRED');
        } catch (\Firebase\JWT\SignatureInvalidException $e) {
            return $this->unauthorized('Invalid signature', 'SIGNATURE_INVALID');
        } catch (\Firebase\JWT\BeforeValidException $e) {
            return $this->unauthorized('Token not yet valid', 'TOKEN_NOT_YET_VALID');
        } catch (\Exception $e) {
            return $this->unauthorized('Invalid token: ' . $e->getMessage());
        }

        // Validate issuer and audience
        $expectedIssuer = Config::get('jwt.issuer', 'secure-device-control-system');
        $expectedAudience = Config::get('jwt.audience', 'secure-device-clients');

        if (($claims->iss ?? '') !== $expectedIssuer) {
            return $this->unauthorized('Invalid issuer', 'INVALID_ISSUER');
        }

        if (($claims->aud ?? '') !== $expectedAudience) {
            return $this->unauthorized('Invalid audience', 'INVALID_AUDIENCE');
        }

        // Extract user and session
        $userId = $claims->sub ?? null;
        $sessionId = $claims->session_id ?? null;

        if (!$userId) {
            return $this->unauthorized('Missing subject claim', 'INVALID_TOKEN');
        }

        // Check if session is revoked
        if ($sessionId) {
            $authToken = AuthToken::where('session_id', $sessionId)
                ->whereNull('revoked_at')
                ->first();

            if (!$authToken) {
                return $this->unauthorized('Session revoked or invalid', 'SESSION_REVOKED');
            }
        }

        // Load user
        $user = User::find($userId);

        if (!$user) {
            return $this->unauthorized('User not found', 'USER_NOT_FOUND');
        }

        // Set authenticated user for the request
        Auth::setUser($user);

        // Attach claims to request for controllers to access
        $request->attributes->set('jwt_claims', $claims);
        $request->attributes->set('jwt_session_id', $sessionId);

        return $next($request);
    }

    /**
     * Verify and decode the JWT token.
     *
     * @param string $token
     * @return object Decoded claims
     * @throws \Exception
     */
    private function verifyToken(string $token): object
    {
        $publicKeyPath = Config::get('jwt.public_key_path');

        if (!$publicKeyPath || !file_exists($publicKeyPath)) {
            throw new \RuntimeException('JWT public key not configured');
        }

        $publicKey = file_get_contents($publicKeyPath);

        if ($publicKey === false) {
            throw new \RuntimeException('Failed to read JWT public key');
        }

        // Determine algorithm from config
        $algorithm = Config::get('jwt.alg', 'RS256');

        // Normalize PS256 to RS256 (consistent with JWTSigner)
        if (strtoupper($algorithm) === 'PS256') {
            $algorithm = 'RS256';
        }

        return JWT::decode($token, new Key($publicKey, $algorithm));
    }

    /**
     * Return an unauthorized response.
     */
    private function unauthorized(string $message, string $code = 'UNAUTHORIZED'): Response
    {
        return response()->json([
            'message' => 'Unauthorized',
            'error' => $message,
            'code' => $code,
        ], 401);
    }
}
