<?php

namespace Tests\Feature;

use App\Models\AuthToken;
use App\Models\Device;
use App\Models\DeviceTelemetryLatest;
use App\Models\TelemetryEvent;
use App\Models\User;
use App\Services\JWT\JWTSigner;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\RequiresPhpExtension;
use Tests\TestCase;

#[RequiresPhpExtension('pdo_sqlite')]
class TelemetryQueryTest extends TestCase
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
    public function admin_can_view_fleet_summary_and_device_latest(): void
    {
        $admin = User::factory()->create(['role' => User::ROLE_ADMIN]);
        Device::create([
            'device_id' => 'dev-telemetry-admin',
            'user_id' => $admin->id,
            'device_name' => 'Telemetry Admin Device',
            'lifecycle_state' => 'active',
            'risk_score' => 41,
            'os_build' => '19045',
            'policy_hash' => 'policy-123',
            'reported_policy_hash' => 'policy-123',
            'compliance_status' => 'non_compliant',
        ]);

        DeviceTelemetryLatest::create([
            'device_id' => 'dev-telemetry-admin',
            'telemetry_scope' => 'telemetry_extended',
            'schema_version' => 'v1',
            'timestamp' => now(),
            'metrics' => ['cpu' => 31, 'ram' => 42, 'disk_usage' => 19, 'network_tx' => 10, 'network_rx' => 12, 'risk_score' => 41, 'os_build' => '26200.8117'],
            'presence_state' => 'online',
            'connection_mode' => 'wss',
            'risk_score' => 41,
            'policy_hash' => 'policy-123',
            'updated_at' => now(),
        ]);

        $jwt = $this->issueJwtFor($admin);

        $this->withHeaders(['Authorization' => 'Bearer '.$jwt])
            ->getJson('/api/telemetry/fleet/summary')
            ->assertOk()
            ->assertJsonPath('fleet.total_devices', 1)
            ->assertJsonPath('fleet.online', 1);

        $this->withHeaders(['Authorization' => 'Bearer '.$jwt])
            ->getJson('/api/telemetry/devices/dev-telemetry-admin/latest')
            ->assertOk()
            ->assertJsonPath('device_id', 'dev-telemetry-admin')
            ->assertJsonPath('presence_state', 'online')
            ->assertJsonPath('resolved_os_build', '26200.8117')
            ->assertJsonPath('resolved_presence_state', 'online')
            ->assertJsonPath('resolved_connection_mode', 'wss')
            ->assertJsonPath('resolved_compliance_status', 'non_compliant')
            ->assertJsonPath('resolved_policy_in_sync', true);
    }

    /** @test */
    public function viewer_cannot_access_other_users_device_telemetry(): void
    {
        $viewer = User::factory()->create(['role' => User::ROLE_VIEWER]);
        $other = User::factory()->create(['role' => User::ROLE_OPERATOR]);

        Device::create([
            'device_id' => 'dev-viewer-own',
            'user_id' => $viewer->id,
            'device_name' => 'Viewer Owned Device',
            'lifecycle_state' => 'active',
        ]);
        Device::create([
            'device_id' => 'dev-viewer-other',
            'user_id' => $other->id,
            'device_name' => 'Other Device',
            'lifecycle_state' => 'active',
        ]);

        TelemetryEvent::create([
            'device_id' => 'dev-viewer-own',
            'telemetry_scope' => 'telemetry_extended',
            'schema_version' => 'v1',
            'timestamp' => now(),
            'metrics' => ['cpu' => 20, 'ram' => 30],
            'source' => 'gateway',
        ]);

        $jwt = $this->issueJwtFor($viewer);
        $headers = ['Authorization' => 'Bearer '.$jwt];

        $this->withHeaders($headers)
            ->getJson('/api/telemetry/devices/dev-viewer-own/history')
            ->assertOk();

        $this->withHeaders($headers)
            ->getJson('/api/telemetry/devices/dev-viewer-other/history')
            ->assertStatus(404);
    }
}
