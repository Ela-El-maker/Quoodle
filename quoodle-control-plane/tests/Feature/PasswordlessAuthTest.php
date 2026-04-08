<?php

namespace Tests\Feature;

use App\Mail\AuthOtpCodeMail;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Mail;
use PHPUnit\Framework\Attributes\RequiresPhpExtension;
use Tests\TestCase;

#[RequiresPhpExtension('pdo_sqlite')]
class PasswordlessAuthTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        if (!file_exists(config('jwt.private_key_path')) || !file_exists(config('jwt.public_key_path'))) {
            $this->markTestSkipped('JWT keys not configured. Run: php artisan jwt:generate-keys');
        }
    }

    /** @test */
    public function it_requests_otp_for_preprovisioned_user_and_returns_challenge(): void
    {
        User::factory()->create([
            'email' => 'viewer@example.com',
            'role' => User::ROLE_VIEWER,
        ]);
        Mail::fake();

        $response = $this->postJson('/api/auth/request-otp', [
            'email' => 'viewer@example.com',
        ]);

        $response->assertOk()
            ->assertJsonStructure([
                'status',
                'challenge_id',
                'resend_after_seconds',
            ])
            ->assertJson([
                'status' => 'otp_sent',
            ]);

        Mail::assertSent(AuthOtpCodeMail::class);
    }

    /** @test */
    public function it_returns_generic_otp_response_for_unknown_email_without_sending_mail(): void
    {
        Mail::fake();

        $response = $this->postJson('/api/auth/request-otp', [
            'email' => 'unknown@example.com',
        ]);

        $response->assertOk()
            ->assertJson([
                'status' => 'otp_sent',
            ])
            ->assertJsonStructure([
                'status',
                'challenge_id',
                'resend_after_seconds',
            ]);

        Mail::assertNothingSent();
    }

    /** @test */
    public function it_verifies_otp_and_issues_tokens(): void
    {
        User::factory()->create([
            'email' => 'operator@example.com',
            'role' => User::ROLE_OPERATOR,
        ]);
        Mail::fake();

        $requestResponse = $this->postJson('/api/auth/request-otp', [
            'email' => 'operator@example.com',
        ]);
        $requestResponse->assertOk();

        $sentCode = null;
        Mail::assertSent(AuthOtpCodeMail::class, function (AuthOtpCodeMail $mail) use (&$sentCode) {
            $sentCode = $mail->code;
            return true;
        });

        $verifyResponse = $this->postJson('/api/auth/verify-otp', [
            'email' => 'operator@example.com',
            'challenge_id' => $requestResponse->json('challenge_id'),
            'otp' => $sentCode,
            'device_fingerprint' => 'test-fingerprint',
        ]);

        $verifyResponse->assertOk()
            ->assertJsonStructure([
                'jwt',
                'refresh_token',
                'session_id',
                'user_id',
                'user_role',
            ])
            ->assertJson([
                'user_role' => User::ROLE_OPERATOR,
            ]);
    }

    /** @test */
    public function it_exchanges_google_code_for_existing_user(): void
    {
        User::factory()->create([
            'email' => 'admin@example.com',
            'role' => User::ROLE_ADMIN,
        ]);

        config()->set('services.google.client_id', 'google-client-id');
        config()->set('services.google.client_secret', 'google-client-secret');

        Http::fake([
            'https://oauth2.googleapis.com/token' => Http::response([
                'access_token' => 'google-access-token',
                'token_type' => 'Bearer',
            ], 200),
            'https://openidconnect.googleapis.com/v1/userinfo' => Http::response([
                'email' => 'admin@example.com',
                'email_verified' => true,
                'name' => 'Admin User',
            ], 200),
        ]);

        $response = $this->postJson('/api/auth/google/exchange', [
            'code' => 'valid-google-code',
            'redirect_uri' => 'http://localhost:3000/api/auth/google/callback',
            'device_fingerprint' => 'test-device',
        ]);

        $response->assertOk()
            ->assertJsonStructure([
                'jwt',
                'refresh_token',
                'session_id',
                'user_id',
                'user_role',
            ])
            ->assertJson([
                'user_role' => User::ROLE_ADMIN,
            ]);
    }
}

