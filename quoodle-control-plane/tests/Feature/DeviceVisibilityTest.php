<?php

namespace Tests\Feature;

use App\Models\AuthToken;
use App\Models\Device;
use App\Models\User;
use App\Services\JWT\JWTSigner;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\RequiresPhpExtension;
use Tests\TestCase;

#[RequiresPhpExtension('pdo_sqlite')]
class DeviceVisibilityTest extends TestCase
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

    /** @test */
    public function admin_can_list_all_devices(): void
    {
        $admin = User::factory()->create(['role' => User::ROLE_ADMIN]);
        $operator = User::factory()->create(['role' => User::ROLE_OPERATOR]);

        Device::create([
            'device_id' => 'dev-admin-visible',
            'user_id' => $admin->id,
            'device_name' => 'Admin Device',
            'lifecycle_state' => 'online',
        ]);
        Device::create([
            'device_id' => 'dev-operator-visible',
            'user_id' => $operator->id,
            'device_name' => 'Operator Device',
            'lifecycle_state' => 'offline',
        ]);
        Device::create([
            'device_id' => 'dev-unclaimed-visible',
            'user_id' => null,
            'device_name' => 'Unclaimed Device',
            'lifecycle_state' => 'pending_pairing',
        ]);

        $jwt = $this->issueJwtFor($admin);
        $response = $this->withHeaders(['Authorization' => 'Bearer '.$jwt])->getJson('/api/devices');

        $response->assertOk();
        $this->assertCount(3, $response->json('devices'));
    }

    /** @test */
    public function operator_only_sees_their_own_claimed_devices(): void
    {
        $operator = User::factory()->create(['role' => User::ROLE_OPERATOR]);
        $other = User::factory()->create(['role' => User::ROLE_VIEWER]);

        Device::create([
            'device_id' => 'dev-operator-1',
            'user_id' => $operator->id,
            'device_name' => 'Operator Device',
            'lifecycle_state' => 'online',
        ]);
        Device::create([
            'device_id' => 'dev-other-1',
            'user_id' => $other->id,
            'device_name' => 'Other Device',
            'lifecycle_state' => 'online',
        ]);
        Device::create([
            'device_id' => 'dev-unclaimed-1',
            'user_id' => null,
            'device_name' => 'Unclaimed Device',
            'lifecycle_state' => 'offline',
        ]);

        $jwt = $this->issueJwtFor($operator);
        $response = $this->withHeaders(['Authorization' => 'Bearer '.$jwt])->getJson('/api/devices');

        $response->assertOk();
        $response->assertJsonCount(1, 'devices');
        $response->assertJsonPath('devices.0.device_id', 'dev-operator-1');
    }

    /** @test */
    public function viewer_cannot_fetch_another_users_device_detail(): void
    {
        $viewer = User::factory()->create(['role' => User::ROLE_VIEWER]);
        $other = User::factory()->create(['role' => User::ROLE_OPERATOR]);

        Device::create([
            'device_id' => 'dev-viewer-own',
            'user_id' => $viewer->id,
            'device_name' => 'Viewer Device',
            'lifecycle_state' => 'online',
        ]);
        Device::create([
            'device_id' => 'dev-operator-own',
            'user_id' => $other->id,
            'device_name' => 'Operator Device',
            'lifecycle_state' => 'online',
        ]);

        $jwt = $this->issueJwtFor($viewer);
        $headers = ['Authorization' => 'Bearer '.$jwt];

        $this->withHeaders($headers)
            ->getJson('/api/devices/dev-viewer-own')
            ->assertOk();

        $this->withHeaders($headers)
            ->getJson('/api/devices/dev-operator-own')
            ->assertStatus(404);
    }

    /** @test */
    public function list_and_detail_include_owner_email(): void
    {
        $operator = User::factory()->create([
            'role' => User::ROLE_OPERATOR,
            'email' => 'operator-owner@example.com',
        ]);

        Device::create([
            'device_id' => 'dev-owner-email',
            'user_id' => $operator->id,
            'device_name' => 'Owner Device',
            'lifecycle_state' => 'online',
        ]);

        $jwt = $this->issueJwtFor($operator);
        $headers = ['Authorization' => 'Bearer '.$jwt];

        $listResponse = $this->withHeaders($headers)->getJson('/api/devices');
        $listResponse->assertOk();
        $listResponse->assertJsonPath('devices.0.owner_email', 'operator-owner@example.com');

        $detailResponse = $this->withHeaders($headers)->getJson('/api/devices/dev-owner-email');
        $detailResponse->assertOk();
        $detailResponse->assertJsonPath('owner_email', 'operator-owner@example.com');
    }
}

