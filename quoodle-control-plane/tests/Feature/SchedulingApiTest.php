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
class SchedulingApiTest extends TestCase
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
    public function operator_can_create_run_and_list_schedules(): void
    {
        $operator = User::factory()->create(['role' => User::ROLE_OPERATOR]);
        Device::create([
            'device_id' => 'sched-dev-001',
            'user_id' => $operator->id,
            'device_name' => 'Schedule Device',
            'lifecycle_state' => 'online',
        ]);

        $jwt = $this->issueJwtFor($operator);
        $headers = ['Authorization' => 'Bearer '.$jwt];

        $createResponse = $this->withHeaders($headers)->postJson('/api/schedules', [
            'name' => 'Hourly Health',
            'method' => 'collect_system_info',
            'params' => [],
            'target_type' => 'device',
            'target_ids' => ['sched-dev-001'],
            'cron_expression' => '0 * * * *',
            'timezone' => 'UTC',
            'enabled' => true,
        ]);

        $createResponse->assertCreated();
        $scheduleId = (string) $createResponse->json('schedule.id');

        $this->withHeaders($headers)
            ->getJson('/api/schedules')
            ->assertOk()
            ->assertJsonCount(1, 'schedules');

        $this->withHeaders($headers)
            ->postJson('/api/schedules/'.$scheduleId.'/run-now')
            ->assertStatus(202)
            ->assertJsonPath('run.job_id', $scheduleId);

        $this->withHeaders($headers)
            ->getJson('/api/schedules/runs?job_id='.$scheduleId)
            ->assertOk()
            ->assertJsonStructure([
                'runs',
                'meta' => ['current_page', 'last_page', 'per_page', 'total'],
            ]);
    }

    /** @test */
    public function high_risk_commands_cannot_be_scheduled(): void
    {
        $operator = User::factory()->create(['role' => User::ROLE_OPERATOR]);
        Device::create([
            'device_id' => 'sched-dev-002',
            'user_id' => $operator->id,
            'device_name' => 'Schedule Device Two',
            'lifecycle_state' => 'online',
        ]);

        $jwt = $this->issueJwtFor($operator);
        $headers = ['Authorization' => 'Bearer '.$jwt];

        $response = $this->withHeaders($headers)->postJson('/api/schedules', [
            'name' => 'Shutdown Daily',
            'method' => 'shutdown_device',
            'params' => ['delay_seconds' => 10],
            'target_type' => 'device',
            'target_ids' => ['sched-dev-002'],
            'cron_expression' => '0 2 * * *',
            'timezone' => 'UTC',
            'enabled' => true,
        ]);

        $response->assertStatus(422);
        $reason = (string) $response->json('reason');
        $this->assertContains($reason, ['method_not_schedulable', 'role_not_allowed']);
    }
}
