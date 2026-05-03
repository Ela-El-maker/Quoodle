<?php

namespace App\Services\Auth;

use App\Models\AuthToken;
use App\Models\User;
use App\Services\JWT\JWTSigner;
use App\Services\Mobile\MobileDeviceTracker;
use Illuminate\Support\Str;

class AuthSessionService
{
    public function __construct(
        private readonly JWTSigner $jwtSigner,
        private readonly MobileDeviceTracker $mobileTracker,
    )
    {
    }

    /**
     * @return array{
     *   jwt: string,
     *   refresh_token: string,
     *   session_id: string,
     *   user_id: string,
     *   user_role: string
     * }
     */
    public function issueForUser(User $user, ?string $deviceFingerprint = null, ?string $pushToken = null): array
    {
        if (method_exists($user, 'isActive') && ! $user->isActive()) {
            throw new \RuntimeException('account_inactive');
        }

        $sessionId = Str::uuid()->toString();
        $refreshToken = Str::uuid()->toString().Str::random(32);

        AuthToken::create([
            'user_id' => $user->id,
            'session_id' => $sessionId,
            'device_fingerprint' => $deviceFingerprint,
            'push_token' => $pushToken,
            'refresh_token_hash' => hash('sha256', $refreshToken),
            'expires_at' => now()->addSeconds((int) config('jwt.refresh_ttl', 3600)),
        ]);

        if (is_string($deviceFingerprint) && trim($deviceFingerprint) !== '') {
            $this->mobileTracker->touch($user, [
                'device_fingerprint' => trim($deviceFingerprint),
                'push_token' => $pushToken,
            ]);
        }

        return [
            'jwt' => $this->jwtSigner->issueForUser($user, $sessionId),
            'refresh_token' => $refreshToken,
            'session_id' => $sessionId,
            'user_id' => $user->id,
            'user_role' => $user->role,
        ];
    }
}
