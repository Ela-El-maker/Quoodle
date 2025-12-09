<?php

namespace App\Services\JWT;

use App\Models\User;
use Firebase\JWT\JWT;
use Illuminate\Support\Str;
use RuntimeException;

class JWTSigner
{
    private string $privateKey;
    private string $publicKey;
    private string $kid;
    private string $algorithm;
    private string $issuer;
    private string $audience;
    private int $ttlSeconds;

    public function __construct()
    {
        $this->kid = config('jwt.kid');
        $this->algorithm = config('jwt.alg');
        $this->issuer = config('jwt.issuer');
        $this->audience = config('jwt.audience');
        $this->ttlSeconds = (int) config('jwt.ttl', 900);
        $this->privateKey = $this->loadKey(config('jwt.private_key_path'));
        $this->publicKey = $this->loadKey(config('jwt.public_key_path'));
    }

    public function issueForUser(User $user, string $sessionId, array $extraClaims = [], ?int $ttlSeconds = null): string
    {
        $now = time();
        $claims = array_merge([
            'iss' => $this->issuer,
            'aud' => $this->audience,
            'iat' => $now,
            'nbf' => $now,
            'exp' => $now + ($ttlSeconds ?? $this->ttlSeconds),
            'jti' => Str::uuid()->toString(),
            'sub' => $user->id,
            'session_id' => $sessionId,
            'email' => $user->email,
        ], $extraClaims);

        return JWT::encode($claims, $this->privateKey, $this->algorithm, $this->kid);
    }

    public function publicKey(): string
    {
        return $this->publicKey;
    }

    public function algorithm(): string
    {
        return $this->algorithm;
    }

    public function kid(): string
    {
        return $this->kid;
    }

    private function loadKey(string $path): string
    {
        if (!file_exists($path) || !is_readable($path)) {
            throw new RuntimeException("JWT key missing or unreadable at {$path}");
        }

        $key = file_get_contents($path);

        if ($key === false) {
            throw new RuntimeException("Unable to read JWT key at {$path}");
        }

        return $key;
    }
}
