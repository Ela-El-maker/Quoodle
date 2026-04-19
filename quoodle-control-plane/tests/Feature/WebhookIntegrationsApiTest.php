<?php

namespace Tests\Feature;

use App\Jobs\DeliverIntegrationWebhookDelivery;
use App\Models\AuthToken;
use App\Models\IntegrationWebhookDelivery;
use App\Models\IntegrationWebhookEndpoint;
use App\Models\User;
use App\Services\JWT\JWTSigner;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Queue;
use PHPUnit\Framework\Attributes\RequiresPhpExtension;
use Tests\TestCase;

#[RequiresPhpExtension('pdo_sqlite')]
class WebhookIntegrationsApiTest extends TestCase
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
    public function operator_can_manage_only_owned_endpoints_while_admin_can_manage_all(): void
    {
        $admin = User::factory()->create(['role' => User::ROLE_ADMIN]);
        $owner = User::factory()->create(['role' => User::ROLE_OPERATOR]);
        $otherOperator = User::factory()->create(['role' => User::ROLE_OPERATOR]);

        $ownerJwt = $this->issueJwtFor($owner);
        $otherJwt = $this->issueJwtFor($otherOperator);
        $adminJwt = $this->issueJwtFor($admin);

        $createResponse = $this->withHeaders(['Authorization' => 'Bearer '.$ownerJwt])
            ->postJson('/api/integrations/webhooks/endpoints', [
                'name' => 'Owner Endpoint',
                'url' => 'https://example.invalid/webhooks',
                'events' => ['command.completed', 'command.failed'],
                'retry_policy' => 'exponential',
                'max_retries' => 3,
                'timeout_ms' => 5000,
            ]);

        $createResponse->assertStatus(201);
        $endpointId = (string) $createResponse->json('endpoint.id');
        $this->assertNotSame('', $endpointId);

        $this->withHeaders(['Authorization' => 'Bearer '.$otherJwt])
            ->postJson("/api/integrations/webhooks/endpoints/{$endpointId}/pause")
            ->assertStatus(403);

        $this->withHeaders(['Authorization' => 'Bearer '.$adminJwt])
            ->postJson("/api/integrations/webhooks/endpoints/{$endpointId}/pause")
            ->assertOk();

        $this->withHeaders(['Authorization' => 'Bearer '.$ownerJwt])
            ->postJson("/api/integrations/webhooks/endpoints/{$endpointId}/resume")
            ->assertOk();

        $listAsOther = $this->withHeaders(['Authorization' => 'Bearer '.$otherJwt])
            ->getJson('/api/integrations/webhooks/endpoints');
        $listAsOther->assertOk();
        $listAsOther->assertJsonPath('endpoints.0.can_manage', false);
        $listAsOther->assertJsonPath('endpoints.0.owner_user_id', $owner->id);
    }

    /** @test */
    public function replay_endpoint_creates_a_new_delivery_and_preserves_traceability(): void
    {
        Queue::fake();

        $operator = User::factory()->create(['role' => User::ROLE_OPERATOR]);
        $jwt = $this->issueJwtFor($operator);

        $endpoint = IntegrationWebhookEndpoint::create([
            'name' => 'Replay Target',
            'url' => 'https://example.invalid/replay',
            'status' => IntegrationWebhookEndpoint::STATUS_ACTIVE,
            'signing_algo' => 'hmac-sha256',
            'retry_policy' => IntegrationWebhookEndpoint::RETRY_NONE,
            'max_retries' => 1,
            'timeout_ms' => 5000,
            'signing_secret_encrypted' => 'whsec_test',
            'created_by' => $operator->id,
            'updated_by' => $operator->id,
        ]);

        $source = IntegrationWebhookDelivery::create([
            'endpoint_id' => $endpoint->id,
            'event_type' => 'command.failed',
            'event_id' => 'evt-source-1',
            'payload_json' => [
                'event_type' => 'command.failed',
                'event_version' => 'v1',
                'event_id' => 'evt-source-1',
                'timestamp' => now()->toIso8601String(),
                'data' => ['command_id' => 'cmd-1'],
            ],
            'attempt' => 2,
            'max_attempts' => 2,
            'status' => IntegrationWebhookDelivery::STATUS_DEAD_LETTER,
            'last_error' => 'http_503',
        ]);

        $response = $this->withHeaders(['Authorization' => 'Bearer '.$jwt])
            ->postJson("/api/integrations/webhooks/deliveries/{$source->id}/replay");

        $response->assertOk();
        $newDeliveryId = (string) $response->json('delivery_id');
        $this->assertNotSame('', $newDeliveryId);

        $newDelivery = IntegrationWebhookDelivery::find($newDeliveryId);
        $this->assertNotNull($newDelivery);
        $this->assertSame($source->id, $newDelivery->replayed_from_delivery_id);
        $this->assertSame(IntegrationWebhookDelivery::STATUS_PENDING, $newDelivery->status);

        Queue::assertPushed(DeliverIntegrationWebhookDelivery::class);
    }
}

