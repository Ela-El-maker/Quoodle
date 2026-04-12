<?php

namespace Tests\Feature;

use App\Models\AuthToken;
use App\Models\Device;
use App\Models\User;
use App\Services\JWT\JWTSigner;
use App\Services\Security\TOTPService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Queue;
use PHPUnit\Framework\Attributes\RequiresPhpExtension;
use Tests\TestCase;

#[RequiresPhpExtension('pdo_sqlite')]
class CommandContractEnforcementTest extends TestCase
{
    use RefreshDatabase;

    private function issueJwtFor(User $user): string
    {
        if (! file_exists(config('jwt.private_key_path')) || ! file_exists(config('jwt.public_key_path'))) {
            $this->markTestSkipped('JWT keys not configured. Run: php artisan jwt:generate-keys');
        }

        $sessionId = 'sess-'.uniqid();
        AuthToken::create([
            'user_id' => $user->id,
            'session_id' => $sessionId,
            'device_fingerprint' => 'test-device',
            'refresh_token_hash' => hash('sha256', 'test-refresh-'.$sessionId),
            'expires_at' => now()->addHour(),
        ]);

        return app(JWTSigner::class)->issueForUser($user, $sessionId);
    }

    private function makeHeaders(User $user): array
    {
        return ['Authorization' => 'Bearer '.$this->issueJwtFor($user)];
    }

    private function createOwnedDevice(User $user, string $deviceId = 'dev-contract'): Device
    {
        return Device::create([
            'device_id' => $deviceId,
            'user_id' => $user->id,
            'device_name' => 'Contract Device',
            'lifecycle_state' => 'online',
        ]);
    }

    private function commandPayload(Device $device, string $method): array
    {
        return [
            'client_message_id' => 'msg-'.uniqid(),
            'device_id' => $device->device_id,
            'method' => $method,
            'params' => [],
            'sensitive' => false,
            'user_id' => $device->user_id,
            'user_role' => User::ROLE_ADMIN,
            // Keep positive-path command tests compliant by default.
            'attestation_status' => 'pass',
        ];
    }

    /** @test */
    public function accepts_canonical_ping_and_rejects_non_canonical_aliases(): void
    {
        Queue::fake();

        $admin = User::factory()->create(['role' => User::ROLE_ADMIN]);
        $device = $this->createOwnedDevice($admin);
        $headers = $this->makeHeaders($admin);

        $this->withHeaders($headers)
            ->postJson('/api/commands', $this->commandPayload($device, 'ping'))
            ->assertCreated()
            ->assertJsonPath('status', 'accepted');

        $this->withHeaders($headers)
            ->postJson('/api/commands', $this->commandPayload($device, 'reboot'))
            ->assertStatus(422)
            ->assertJsonPath('status', 'rejected')
            ->assertJsonPath('reason', 'unknown_command');

        $this->withHeaders($headers)
            ->postJson('/api/commands', $this->commandPayload($device, 'shutdown'))
            ->assertStatus(422)
            ->assertJsonPath('status', 'rejected')
            ->assertJsonPath('reason', 'unknown_command');

        $this->withHeaders($headers)
            ->postJson('/api/commands', $this->commandPayload($device, 'logout'))
            ->assertStatus(422)
            ->assertJsonPath('status', 'rejected')
            ->assertJsonPath('reason', 'unknown_command');
    }

    /** @test */
    public function rejects_runtime_unsupported_methods_at_dispatch_gate(): void
    {
        Queue::fake();

        $admin = User::factory()->create(['role' => User::ROLE_ADMIN]);
        $device = $this->createOwnedDevice($admin);

        $this->withHeaders($this->makeHeaders($admin))
            ->postJson('/api/commands', $this->commandPayload($device, 'lock_screen'))
            ->assertStatus(422)
            ->assertJsonPath('status', 'rejected')
            ->assertJsonPath('reason', 'not_supported_runtime');
    }

    /** @test */
    public function capabilities_endpoint_returns_canonical_and_runtime_supported_sets(): void
    {
        $admin = User::factory()->create(['role' => User::ROLE_ADMIN]);
        $device = $this->createOwnedDevice($admin, 'dev-capabilities');

        $response = $this->withHeaders($this->makeHeaders($admin))
            ->getJson('/api/commands/capabilities?device_id='.$device->device_id);

        $response->assertOk()
            ->assertJsonPath('runtime_supported_methods.0', 'ping')
            ->assertJsonPath('runtime_supported_methods.1', 'reboot_device')
            ->assertJsonPath('runtime_supported_methods.2', 'shutdown_device')
            ->assertJsonPath('runtime_supported_methods.3', 'collect_system_info')
            ->assertJsonPath('runtime_supported_methods.4', 'screenshot');

        $canonical = $response->json('canonical_methods');
        $this->assertContains('logout_user', $canonical);
        $this->assertContains('collect_system_info', $canonical);
        $this->assertContains('screenshot', $canonical);
        $this->assertContains('reboot_device', $canonical);
        $this->assertContains('shutdown_device', $canonical);
        $this->assertNotContains('sysinfo', $canonical);
        $this->assertNotContains('logout', $canonical);
        $this->assertNotContains('reboot', $canonical);
        $this->assertNotContains('shutdown', $canonical);

        $rejectionReasons = $response->json('rejection_reasons');
        $this->assertSame('not_supported_runtime', $rejectionReasons['lock_screen'] ?? null);
    }

    /** @test */
    public function canonical_reboot_requires_valid_2fa_code(): void
    {
        Queue::fake();

        $secret = app(TOTPService::class)->generateSecretBase32();
        $code = app(TOTPService::class)->generate($secret, intdiv(time(), 30));

        $admin = User::factory()->create([
            'role' => User::ROLE_ADMIN,
            'two_factor_enabled' => true,
            'two_factor_secret' => $secret,
        ]);
        $device = $this->createOwnedDevice($admin, 'dev-reboot');

        $payload = $this->commandPayload($device, 'reboot_device');
        $payload['two_factor_code'] = $code;
        $payload['sensitive'] = true;

        $this->withHeaders($this->makeHeaders($admin))
            ->postJson('/api/commands', $payload)
            ->assertCreated()
            ->assertJsonPath('status', 'accepted');
    }

    /** @test */
    public function collect_system_info_is_runtime_supported_and_accepted(): void
    {
        Queue::fake();

        $admin = User::factory()->create(['role' => User::ROLE_ADMIN]);
        $device = $this->createOwnedDevice($admin, 'dev-collect-info');

        $this->withHeaders($this->makeHeaders($admin))
            ->postJson('/api/commands', $this->commandPayload($device, 'collect_system_info'))
            ->assertCreated()
            ->assertJsonPath('status', 'accepted');
    }

    /** @test */
    public function screenshot_is_runtime_supported_and_accepts_format_contract(): void
    {
        Queue::fake();

        $admin = User::factory()->create(['role' => User::ROLE_ADMIN]);
        $device = $this->createOwnedDevice($admin, 'dev-screenshot');

        $payload = $this->commandPayload($device, 'screenshot');
        $payload['params'] = [
            'resolution' => '1080p',
            'format' => 'jpeg',
        ];

        $this->withHeaders($this->makeHeaders($admin))
            ->postJson('/api/commands', $payload)
            ->assertCreated()
            ->assertJsonPath('status', 'accepted');
    }

    /** @test */
    public function screenshot_bypasses_non_compliant_rejection_gate(): void
    {
        Queue::fake();

        $admin = User::factory()->create(['role' => User::ROLE_ADMIN]);
        $device = $this->createOwnedDevice($admin, 'dev-screenshot-bypass');

        $payload = $this->commandPayload($device, 'screenshot');
        $payload['attestation_status'] = 'failed';

        $this->withHeaders($this->makeHeaders($admin))
            ->postJson('/api/commands', $payload)
            ->assertCreated()
            ->assertJsonPath('status', 'accepted')
            ->assertJsonPath('compliance.status', 'non_compliant');
    }
}
