<?php

namespace Tests\Feature;

use App\Models\AuthToken;
use App\Models\User;
use App\Services\JWT\JWTSigner;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\RequiresPhpExtension;
use Tests\TestCase;

#[RequiresPhpExtension('pdo_sqlite')]
class MeEndpointTest extends TestCase
{
    use RefreshDatabase;

    private User $user;
    private JWTSigner $jwtSigner;
    private string $sessionId;

    protected function setUp(): void
    {
        parent::setUp();

        if (!file_exists(config('jwt.private_key_path')) || !file_exists(config('jwt.public_key_path'))) {
            $this->markTestSkipped('JWT keys not configured. Run: php artisan jwt:generate-keys');
        }

        $this->jwtSigner = app(JWTSigner::class);

        $this->user = User::factory()->create([
            'display_name' => 'Admin User',
            'email' => 'admin@example.com',
            'role' => User::ROLE_ADMIN,
            'two_factor_enabled' => true,
        ]);

        $this->sessionId = 'me-endpoint-session-'.uniqid();

        AuthToken::create([
            'user_id' => $this->user->id,
            'session_id' => $this->sessionId,
            'device_fingerprint' => 'ui-device',
            'refresh_token_hash' => hash('sha256', 'refresh-token'),
            'expires_at' => now()->addHour(),
        ]);
    }

    /** @test */
    public function it_returns_authenticated_user_profile_with_valid_jwt(): void
    {
        $jwt = $this->jwtSigner->issueForUser($this->user, $this->sessionId);

        $response = $this->withHeaders([
            'Authorization' => 'Bearer '.$jwt,
        ])->getJson('/api/me');

        $response->assertOk()
            ->assertJson([
                'user_id' => $this->user->id,
                'email' => 'admin@example.com',
                'display_name' => 'Admin User',
                'user_role' => User::ROLE_ADMIN,
                'two_factor_enabled' => true,
            ]);
    }

    /** @test */
    public function it_returns_unauthorized_without_jwt(): void
    {
        $response = $this->getJson('/api/me');

        $response->assertStatus(401)
            ->assertJson([
                'message' => 'Unauthorized',
                'code' => 'UNAUTHORIZED',
            ]);
    }

    /** @test */
    public function it_returns_unauthorized_for_revoked_session(): void
    {
        AuthToken::where('session_id', $this->sessionId)->update([
            'revoked_at' => now(),
        ]);

        $jwt = $this->jwtSigner->issueForUser($this->user, $this->sessionId);

        $response = $this->withHeaders([
            'Authorization' => 'Bearer '.$jwt,
        ])->getJson('/api/me');

        $response->assertStatus(401)
            ->assertJson([
                'message' => 'Unauthorized',
                'code' => 'SESSION_REVOKED',
            ]);
    }
}
