<?php

namespace Tests\Feature;

use App\Models\Alert;
use App\Models\AuthToken;
use App\Models\Command;
use App\Models\Device;
use App\Models\User;
use App\Services\JWT\JWTSigner;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

class ApiSmokeTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        if (!extension_loaded('pdo_sqlite')) {
            $this->markTestSkipped('pdo_sqlite not available for in-memory tests.');
        }

        parent::setUp();
    }

    protected function getEnvironmentSetUp($app): void
    {
        $app['config']->set('database.default', 'sqlite');
        $app['config']->set('database.connections.sqlite.database', ':memory:');
        $app['config']->set('policy.master_hash', 'test-policy-hash');
        $app['config']->set('policy.version', 'test-policy-version');
        $app['config']->set('services.fastapi.require_webhook_signature', false);
    }

    private function ensureJwtKeys(): void
    {
        if (!file_exists(config('jwt.private_key_path')) || !file_exists(config('jwt.public_key_path'))) {
            $this->markTestSkipped('JWT keys not configured. Run: php artisan jwt:generate-keys');
        }
    }

    /** @test */
    public function it_smoke_tests_core_api_and_webhooks(): void
    {
        $this->ensureJwtKeys();

        $user = User::factory()->create([
            'email' => 'smoke@example.com',
            'password' => bcrypt('password123'),
            'role' => 'admin',
        ]);

        $sessionId = 'smoke-session-' . Str::uuid()->toString();
        AuthToken::create([
            'user_id' => $user->id,
            'session_id' => $sessionId,
            'device_fingerprint' => 'smoke-device',
            'refresh_token_hash' => hash('sha256', 'smoke-refresh'),
            'expires_at' => now()->addHour(),
        ]);

        $jwt = app(JWTSigner::class)->issueForUser($user, $sessionId);
        $headers = ['Authorization' => 'Bearer ' . $jwt];

        $device = Device::create([
            'device_id' => 'device-001',
            'device_name' => 'Smoke Device',
            'user_id' => $user->id,
            'lifecycle_state' => 'online',
            'policy_hash' => 'test-policy-hash',
            'compliance_status' => 'compliant',
            'last_seen' => now(),
            'os_build' => 'win-11',
        ]);

        $command = Command::create([
            'id' => 'cmd-001',
            'client_message_id' => 'client-msg-001',
            'device_id' => $device->device_id,
            'method' => 'lock_screen',
            'params' => [],
            'state' => 'queued',
            'queued_at' => now(),
            'ttl_seconds' => 300,
            'expires_at' => now()->addMinutes(5),
        ]);

        $alert = Alert::create([
            'alert_id' => 'alert-001',
            'device_id' => $device->device_id,
            'severity' => 'high',
            'category' => 'policy',
            'message' => 'Policy mismatch',
            'timestamp' => now(),
            'acknowledged' => false,
        ]);

        $this->getJson('/api/devices', $headers)->assertOk()->assertJsonStructure(['devices']);
        $this->getJson("/api/devices/{$device->device_id}", $headers)->assertOk()->assertJsonStructure([
            'device_id',
            'device_name',
            'lifecycle_state',
            'compliance',
            'telemetry_latest',
        ]);
        $this->getJson("/api/devices/{$device->device_id}/commands", $headers)->assertOk()->assertJsonStructure(['commands']);
        $this->getJson("/api/commands/{$command->id}", $headers)->assertOk()->assertJsonStructure(['command_id', 'state', 'result']);
        $this->getJson('/api/alerts', $headers)->assertOk()->assertJsonStructure(['alerts']);

        $this->postJson('/api/alerts/' . $alert->alert_id . '/ack', [], $headers)
            ->assertOk()
            ->assertJson(['status' => 'ok']);

        $this->postJson('/api/policy/evaluate', [
            'device_id' => $device->device_id,
            'device_lifecycle_state' => 'online',
            'method' => 'lock_screen',
            'params' => [],
            'policy_hash' => 'test-policy-hash',
            'timestamp' => now()->toIso8601String(),
            'user_id' => (string) $user->id,
            'user_role' => 'admin',
            'two_factor_verified' => true,
        ], $headers)->assertOk()->assertJsonStructure(['decision', 'reason']);

        $this->postJson('/api/session/push-token', [
            'push_token' => 'smoke-push-token',
        ], $headers)->assertOk()->assertJson(['status' => 'ok']);

        $this->withoutMiddleware()
            ->postJson('/api/v1/webhook/device/online', [
                'device_id' => $device->device_id,
                'session_id' => 'session-1',
                'connected_at' => now()->toIso8601String(),
            ])->assertOk()->assertJson(['status' => 'ack']);

        $this->withoutMiddleware()
            ->postJson('/api/v1/webhook/command/ack', [
                'command_id' => $command->id,
                'device_id' => $device->device_id,
                'status' => 'received',
                'timestamp' => now()->toIso8601String(),
            ])->assertOk()->assertJson(['status' => 'ok']);

        $this->withoutMiddleware()
            ->postJson('/api/v1/webhook/command/result', [
                'command_id' => $command->id,
                'device_id' => $device->device_id,
                'trace_id' => 'trace-001',
                'execution_state' => 'completed',
                'result' => ['status' => 'success'],
                'timestamp' => now()->toIso8601String(),
            ])->assertOk()->assertJson(['status' => 'received']);
    }
}
