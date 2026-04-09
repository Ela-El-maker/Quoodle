<?php

namespace Tests\Feature;

use App\Models\AuthToken;
use App\Models\Command;
use App\Models\Device;
use App\Models\User;
use App\Services\JWT\JWTSigner;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\RequiresPhpExtension;
use Tests\TestCase;

#[RequiresPhpExtension('pdo_sqlite')]
class CommandVisibilityTest extends TestCase
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

    private function createCommand(string $deviceId, string $method): Command
    {
        return Command::create([
            'client_message_id' => (string) Str::uuid(),
            'device_id' => $deviceId,
            'method' => $method,
            'params' => ['foo' => 'bar'],
            'sensitive' => false,
            'state' => 'queued',
            'status' => 'accepted',
            'reason' => null,
            'trace_id' => (string) Str::uuid(),
            'queued_at' => now(),
            'execution_state' => 'queued',
        ]);
    }

    /** @test */
    public function admin_can_list_all_commands(): void
    {
        $admin = User::factory()->create(['role' => User::ROLE_ADMIN]);
        $operator = User::factory()->create(['role' => User::ROLE_OPERATOR]);

        Device::create([
            'device_id' => 'dev-admin-cmd',
            'user_id' => $admin->id,
            'device_name' => 'Admin Device',
            'lifecycle_state' => 'online',
        ]);
        Device::create([
            'device_id' => 'dev-operator-cmd',
            'user_id' => $operator->id,
            'device_name' => 'Operator Device',
            'lifecycle_state' => 'online',
        ]);

        $this->createCommand('dev-admin-cmd', 'ping');
        $this->createCommand('dev-operator-cmd', 'lock_screen');

        $jwt = $this->issueJwtFor($admin);
        $response = $this->withHeaders(['Authorization' => 'Bearer '.$jwt])->getJson('/api/commands?limit=10');

        $response->assertOk();
        $response->assertJsonCount(2, 'commands');
    }

    /** @test */
    public function viewer_only_sees_their_own_commands_and_not_others(): void
    {
        $viewer = User::factory()->create(['role' => User::ROLE_VIEWER]);
        $other = User::factory()->create(['role' => User::ROLE_OPERATOR]);

        Device::create([
            'device_id' => 'dev-viewer-cmd',
            'user_id' => $viewer->id,
            'device_name' => 'Viewer Device',
            'lifecycle_state' => 'online',
        ]);
        Device::create([
            'device_id' => 'dev-other-cmd',
            'user_id' => $other->id,
            'device_name' => 'Other Device',
            'lifecycle_state' => 'online',
        ]);

        $ownCommand = $this->createCommand('dev-viewer-cmd', 'ping');
        $otherCommand = $this->createCommand('dev-other-cmd', 'lock_screen');

        $jwt = $this->issueJwtFor($viewer);
        $headers = ['Authorization' => 'Bearer '.$jwt];

        $listResponse = $this->withHeaders($headers)->getJson('/api/commands?limit=10');
        $listResponse->assertOk();
        $listResponse->assertJsonCount(1, 'commands');
        $listResponse->assertJsonPath('commands.0.command_id', $ownCommand->id);

        $this->withHeaders($headers)
            ->getJson('/api/commands/'.$ownCommand->id)
            ->assertOk();

        $this->withHeaders($headers)
            ->getJson('/api/commands/'.$otherCommand->id)
            ->assertStatus(404);

        $this->withHeaders($headers)
            ->getJson('/api/devices/dev-viewer-cmd/commands?limit=10')
            ->assertOk();

        $this->withHeaders($headers)
            ->getJson('/api/devices/dev-other-cmd/commands?limit=10')
            ->assertStatus(404);
    }
}

