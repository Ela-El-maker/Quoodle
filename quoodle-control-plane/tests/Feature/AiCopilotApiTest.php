<?php

namespace Tests\Feature;

use App\Models\AuthToken;
use App\Models\Device;
use App\Models\User;
use App\Services\JWT\JWTSigner;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Http;
use PHPUnit\Framework\Attributes\RequiresPhpExtension;
use Tests\TestCase;

#[RequiresPhpExtension('pdo_sqlite')]
class AiCopilotApiTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        config([
            'ai.global_enabled' => true,
            'ai.device_copilot_enabled' => true,
            'services.ai_sidecar.base_url' => 'http://ai-sidecar:8000',
            'services.ai_sidecar.service_token' => 'sidecar-token',
            'services.fastapi.base_url' => 'http://localhost:8000/api/v1',
        ]);
    }

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
    public function authorized_actor_gets_persisted_device_health_answer_artifact(): void
    {
        $user = User::factory()->create(['role' => User::ROLE_OPERATOR]);
        Device::create([
            'device_id' => 'dev-ai-001',
            'user_id' => $user->id,
            'device_name' => 'AI Device',
            'lifecycle_state' => 'degraded',
            'risk_score' => 42,
            'compliance_status' => 'non_compliant',
        ]);

        Http::fake([
            'http://ai-sidecar:8000/internal/ai/chat/ask' => Http::response($this->sidecarSuccessPayload(), 200),
            '*' => Http::response(['status' => 'ok'], 200),
        ]);

        $jwt = $this->issueJwtFor($user);
        $response = $this->withHeaders(['Authorization' => 'Bearer '.$jwt])
            ->postJson('/api/ai/copilot/ask', [
                'query' => 'Why is this device unhealthy?',
                'selected_refs' => ['device_id' => 'dev-ai-001'],
                'ui_surface' => 'web.device_detail',
            ]);

        $response->assertOk();
        $response->assertJsonPath('artifact.artifact_type', 'answer');
        $this->assertNotEmpty((string) $response->json('artifact.artifact_id'));
        $this->assertNotEmpty((string) $response->json('conversation_id'));

        $this->assertDatabaseCount('ai_conversations', 1);
        $this->assertDatabaseCount('ai_artifacts', 1);
        $this->assertDatabaseCount('ai_evidence_refs', 2);
        $this->assertDatabaseCount('ai_tool_calls', 2);
        $this->assertDatabaseHas('ai_model_calls', [
            'provider' => 'qwen',
            'status' => 'ok',
        ]);
        $this->assertDatabaseHas('audit_trail', [
            'event_type' => 'ai.copilot.answer',
            'device_id' => 'dev-ai-001',
        ]);
    }

    /** @test */
    public function unauthorized_device_scope_returns_forbidden_and_never_calls_sidecar(): void
    {
        $viewer = User::factory()->create(['role' => User::ROLE_VIEWER]);
        $operator = User::factory()->create(['role' => User::ROLE_OPERATOR]);

        Device::create([
            'device_id' => 'dev-owned-by-operator',
            'user_id' => $operator->id,
            'device_name' => 'Operator Device',
            'lifecycle_state' => 'online',
        ]);

        Http::fake();

        $jwt = $this->issueJwtFor($viewer);
        $response = $this->withHeaders(['Authorization' => 'Bearer '.$jwt])
            ->postJson('/api/ai/copilot/ask', [
                'query' => 'Why is this device unhealthy?',
                'selected_refs' => ['device_id' => 'dev-owned-by-operator'],
                'ui_surface' => 'web.device_detail',
            ]);

        $response->assertStatus(403);
        $response->assertJsonPath('message', 'forbidden');
        Http::assertNothingSent();
    }

    /** @test */
    public function sidecar_unavailable_returns_service_unavailable_and_records_error_row(): void
    {
        $user = User::factory()->create(['role' => User::ROLE_OPERATOR]);
        Device::create([
            'device_id' => 'dev-ai-002',
            'user_id' => $user->id,
            'device_name' => 'AI Device 2',
            'lifecycle_state' => 'online',
        ]);

        Http::fake([
            'http://ai-sidecar:8000/internal/ai/chat/ask' => Http::response(['error' => 'down'], 503),
            '*' => Http::response(['status' => 'ok'], 200),
        ]);

        $jwt = $this->issueJwtFor($user);
        $response = $this->withHeaders(['Authorization' => 'Bearer '.$jwt])
            ->postJson('/api/ai/copilot/ask', [
                'query' => 'What changed on this device?',
                'selected_refs' => ['device_id' => 'dev-ai-002'],
                'ui_surface' => 'web.device_detail',
            ]);

        $response->assertStatus(503);
        $response->assertJsonPath('message', 'copilot_unavailable');
        $this->assertDatabaseHas('ai_model_calls', [
            'provider' => 'sidecar',
            'status' => 'error',
            'error_code' => 'sidecar_unavailable',
        ]);
    }

    /** @test */
    public function actor_can_reload_persisted_copilot_conversation_transcript(): void
    {
        $user = User::factory()->create(['role' => User::ROLE_OPERATOR]);
        Device::create([
            'device_id' => 'dev-ai-003',
            'user_id' => $user->id,
            'device_name' => 'AI Device 3',
            'lifecycle_state' => 'online',
        ]);

        Http::fake([
            'http://ai-sidecar:8000/internal/ai/chat/ask' => Http::response($this->sidecarSuccessPayload(), 200),
            '*' => Http::response(['status' => 'ok'], 200),
        ]);

        $jwt = $this->issueJwtFor($user);
        $askResponse = $this->withHeaders(['Authorization' => 'Bearer '.$jwt])
            ->postJson('/api/ai/copilot/ask', [
                'query' => 'Why is this device unhealthy?',
                'selected_refs' => ['device_id' => 'dev-ai-003'],
                'ui_surface' => 'web.device_detail',
            ]);
        $askResponse->assertOk();
        $conversationId = (string) $askResponse->json('conversation_id');

        $conversationResponse = $this->withHeaders(['Authorization' => 'Bearer '.$jwt])
            ->getJson('/api/ai/copilot/conversations/'.rawurlencode($conversationId));

        $conversationResponse->assertOk();
        $conversationResponse->assertJsonPath('conversation_id', $conversationId);
        $this->assertGreaterThan(0, count($conversationResponse->json('transcript') ?? []));
    }

    /**
     * @return array<string, mixed>
     */
    private function sidecarSuccessPayload(): array
    {
        return [
            'status' => 'ok',
            'assistant_message' => 'Evidence suggests intermittent transport issues caused degraded health.',
            'confidence' => [
                'score' => 0.73,
                'band' => 'medium',
            ],
            'freshness_seconds' => 9,
            'evidence_refs' => [
                [
                    'source_type' => 'get_device_summary',
                    'source_id' => 'dev-ai-001',
                    'source_timestamp' => '2026-04-23T10:00:00Z',
                    'excerpt_summary' => 'Device state=degraded risk=42',
                    'excerpt_hash' => 'sha256:e1',
                    'freshness_seconds' => 7,
                    'confidence_weight' => 0.5,
                ],
                [
                    'source_type' => 'get_latest_telemetry',
                    'source_id' => 'dev-ai-001',
                    'source_timestamp' => '2026-04-23T10:00:02Z',
                    'excerpt_summary' => 'Telemetry cpu=81 ram=67',
                    'excerpt_hash' => 'sha256:e2',
                    'freshness_seconds' => 9,
                    'confidence_weight' => 0.5,
                ],
            ],
            'artifact' => [
                'artifact_type' => 'answer',
                'state' => 'created',
                'summary' => 'Intermittent transport instability',
                'prompt_hash' => 'sha256:p1',
                'tool_call_set_hash' => 'sha256:t1',
            ],
            'tool_calls' => [
                [
                    'tool_name' => 'get_device_summary',
                    'status' => 'ok',
                    'duration_ms' => 11,
                    'rows_returned' => 1,
                    'input_hash' => 'sha256:i1',
                    'output_hash' => 'sha256:o1',
                    'scope_hash' => 'sha256:s1',
                ],
                [
                    'tool_name' => 'get_latest_telemetry',
                    'status' => 'ok',
                    'duration_ms' => 13,
                    'rows_returned' => 1,
                    'input_hash' => 'sha256:i2',
                    'output_hash' => 'sha256:o2',
                    'scope_hash' => 'sha256:s2',
                ],
            ],
            'model_call' => [
                'provider' => 'qwen',
                'model' => 'qwen3.6-plus',
                'api_mode' => 'responses',
                'provider_response_id' => 'resp_test_1',
                'request_hash' => 'sha256:r1',
                'tool_call_set_hash' => 'sha256:t1',
                'input_tokens' => 321,
                'output_tokens' => 109,
                'latency_ms' => 812,
                'status' => 'ok',
                'error_code' => null,
            ],
            'guardrail_events' => [
                [
                    'event_type' => 'guardrail.precheck',
                    'severity' => 'info',
                    'detail' => ['result' => 'ok'],
                ],
            ],
        ];
    }
}
