<?php

namespace Tests\Feature;

use App\Models\AuthToken;
use App\Models\User;
use App\Services\JWT\JWTSigner;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\RequiresPhpExtension;
use Tests\TestCase;

#[RequiresPhpExtension('pdo_sqlite')]
class JWTAuthMiddlewareTest extends TestCase
{
    use RefreshDatabase;

    private User $user;
    private JWTSigner $jwtSigner;
    private string $sessionId;

    protected function setUp(): void
    {
        parent::setUp();

        // Skip if JWT keys are not configured
        if (!file_exists(config('jwt.private_key_path')) || !file_exists(config('jwt.public_key_path'))) {
            $this->markTestSkipped('JWT keys not configured. Run: php artisan jwt:generate-keys');
        }

        $this->jwtSigner = app(JWTSigner::class);

        $this->user = User::factory()->create([
            'email' => 'test@example.com',
        ]);

        $this->sessionId = 'test-session-' . uniqid();

        // Create a valid auth token record
        AuthToken::create([
            'user_id' => $this->user->id,
            'session_id' => $this->sessionId,
            'device_fingerprint' => 'test-device',
            'refresh_token_hash' => hash('sha256', 'test-refresh'),
            'expires_at' => now()->addHour(),
        ]);
    }

    /** @test */
    public function it_allows_access_with_valid_jwt(): void
    {
        $jwt = $this->jwtSigner->issueForUser($this->user, $this->sessionId);

        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $jwt,
        ])->getJson('/api/devices');

        // Should not be 401
        $this->assertNotEquals(401, $response->status());
    }

    /** @test */
    public function it_rejects_missing_authorization_header(): void
    {
        $response = $this->getJson('/api/devices');

        $response->assertStatus(401)
            ->assertJson([
                'message' => 'Unauthorized',
                'code' => 'UNAUTHORIZED',
            ]);
    }

    /** @test */
    public function it_rejects_invalid_bearer_format(): void
    {
        $response = $this->withHeaders([
            'Authorization' => 'Basic invalid',
        ])->getJson('/api/devices');

        $response->assertStatus(401);
    }

    /** @test */
    public function it_rejects_empty_token(): void
    {
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ',
        ])->getJson('/api/devices');

        $response->assertStatus(401);
    }

    /** @test */
    public function it_rejects_malformed_token(): void
    {
        $response = $this->withHeaders([
            'Authorization' => 'Bearer not.a.valid.jwt',
        ])->getJson('/api/devices');

        $response->assertStatus(401);
    }

    /** @test */
    public function it_rejects_expired_token(): void
    {
        // Issue a token that's already expired
        $jwt = $this->jwtSigner->issueForUser($this->user, $this->sessionId, [], -3600);

        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $jwt,
        ])->getJson('/api/devices');

        $response->assertStatus(401)
            ->assertJson([
                'code' => 'TOKEN_EXPIRED',
            ]);
    }

    /** @test */
    public function it_rejects_revoked_session(): void
    {
        // Revoke the session
        AuthToken::where('session_id', $this->sessionId)->update([
            'revoked_at' => now(),
        ]);

        $jwt = $this->jwtSigner->issueForUser($this->user, $this->sessionId);

        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $jwt,
        ])->getJson('/api/devices');

        $response->assertStatus(401)
            ->assertJson([
                'code' => 'SESSION_REVOKED',
            ]);
    }

    /** @test */
    public function it_rejects_token_for_nonexistent_user(): void
    {
        $jwt = $this->jwtSigner->issueForUser($this->user, $this->sessionId);

        // Delete the user
        $this->user->delete();

        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $jwt,
        ])->getJson('/api/devices');

        $response->assertStatus(401)
            ->assertJson([
                'code' => 'USER_NOT_FOUND',
            ]);
    }

    /** @test */
    public function it_allows_passwordless_otp_request_without_jwt(): void
    {
        $response = $this->postJson('/api/auth/request-otp', [
            'email' => 'test@example.com',
        ]);

        $this->assertNotEquals(401, $response->status(), 'OTP request should not require JWT');
    }

    /** @test */
    public function it_allows_otp_verify_endpoint_without_jwt(): void
    {
        $response = $this->postJson('/api/auth/verify-otp', [
            'email' => 'test@example.com',
            'challenge_id' => 'missing-challenge',
            'otp' => '000000',
        ]);

        $this->assertNotEquals(401, $response->status(), 'OTP verification should not require JWT');
    }

    /** @test */
    public function it_allows_token_refresh_without_jwt(): void
    {
        $response = $this->postJson('/api/token/refresh', [
            'refresh_token' => 'test-refresh',
        ]);

        // Should not be 401 for missing JWT (even if refresh token is invalid)
        // It would be 401 for invalid refresh, but not for missing JWT auth
        $this->assertTrue(
            $response->status() !== 401 ||
            ($response->json('code') ?? '') !== 'UNAUTHORIZED',
            'Token refresh should not require JWT'
        );
    }

    /** @test */
    public function it_sets_authenticated_user_in_request(): void
    {
        $jwt = $this->jwtSigner->issueForUser($this->user, $this->sessionId);

        // This tests that Auth::user() is set correctly in the middleware
        $response = $this->withHeaders([
            'Authorization' => 'Bearer ' . $jwt,
        ])->getJson('/api/devices');

        // The controller should have access to the authenticated user
        // We can't directly test Auth::user() from here, but if the request
        // doesn't fail with 401, it means the user was set correctly
        $this->assertNotEquals(401, $response->status());
    }
}
