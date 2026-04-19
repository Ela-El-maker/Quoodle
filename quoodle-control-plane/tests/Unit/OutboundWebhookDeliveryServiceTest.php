<?php

namespace Tests\Unit;

use App\Models\IntegrationWebhookDelivery;
use App\Models\IntegrationWebhookEndpoint;
use App\Models\User;
use App\Services\Integrations\Webhooks\OutboundWebhookDeliveryService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Client\Request as ClientRequest;
use Illuminate\Support\Facades\Http;
use PHPUnit\Framework\Attributes\RequiresPhpExtension;
use Tests\TestCase;

#[RequiresPhpExtension('pdo_sqlite')]
class OutboundWebhookDeliveryServiceTest extends TestCase
{
    use RefreshDatabase;

    /** @test */
    public function it_signs_payload_using_timestamp_event_id_and_raw_body(): void
    {
        $owner = User::factory()->create();
        $endpoint = IntegrationWebhookEndpoint::create([
            'name' => 'Sig Test',
            'url' => 'https://receiver.invalid/webhooks',
            'status' => IntegrationWebhookEndpoint::STATUS_ACTIVE,
            'signing_algo' => 'hmac-sha256',
            'retry_policy' => IntegrationWebhookEndpoint::RETRY_NONE,
            'max_retries' => 0,
            'timeout_ms' => 5000,
            'signing_secret_encrypted' => 'whsec_sig_test',
            'created_by' => $owner->id,
            'updated_by' => $owner->id,
        ]);

        $delivery = IntegrationWebhookDelivery::create([
            'endpoint_id' => $endpoint->id,
            'event_type' => 'command.completed',
            'event_id' => 'evt_sig_1',
            'payload_json' => [
                'event_type' => 'command.completed',
                'event_version' => 'v1',
                'event_id' => 'evt_sig_1',
                'timestamp' => now()->toIso8601String(),
                'data' => ['command_id' => 'cmd-123'],
            ],
            'attempt' => 0,
            'max_attempts' => 1,
            'status' => IntegrationWebhookDelivery::STATUS_PENDING,
            'next_attempt_at' => now(),
        ]);

        Http::fake(function (ClientRequest $request) {
            $timestamp = (string) ($request->header('X-Quoodle-Timestamp')[0] ?? '');
            $eventId = (string) ($request->header('X-Quoodle-Event-Id')[0] ?? '');
            $signature = (string) ($request->header('X-Quoodle-Signature')[0] ?? '');
            $body = (string) $request->body();

            $expected = hash_hmac('sha256', $timestamp.'.'.$eventId.'.'.$body, 'whsec_sig_test');
            $this->assertSame($expected, $signature);
            $this->assertSame('evt_sig_1', $eventId);

            return Http::response('ok', 200);
        });

        $outcome = app(OutboundWebhookDeliveryService::class)->deliver($delivery->id);
        $this->assertFalse($outcome['retry']);

        $delivery->refresh();
        $this->assertSame(IntegrationWebhookDelivery::STATUS_SENT, $delivery->status);
        $this->assertSame(200, $delivery->http_status);
    }

    /** @test */
    public function it_marks_dead_letter_when_retry_policy_is_none_and_delivery_fails(): void
    {
        $owner = User::factory()->create();
        $endpoint = IntegrationWebhookEndpoint::create([
            'name' => 'No Retry Endpoint',
            'url' => 'https://receiver.invalid/no-retry',
            'status' => IntegrationWebhookEndpoint::STATUS_ACTIVE,
            'signing_algo' => 'hmac-sha256',
            'retry_policy' => IntegrationWebhookEndpoint::RETRY_NONE,
            'max_retries' => 0,
            'timeout_ms' => 5000,
            'signing_secret_encrypted' => 'whsec_no_retry',
            'created_by' => $owner->id,
            'updated_by' => $owner->id,
        ]);

        $delivery = IntegrationWebhookDelivery::create([
            'endpoint_id' => $endpoint->id,
            'event_type' => 'command.failed',
            'event_id' => 'evt_fail_1',
            'payload_json' => [
                'event_type' => 'command.failed',
                'event_version' => 'v1',
                'event_id' => 'evt_fail_1',
                'timestamp' => now()->toIso8601String(),
                'data' => ['command_id' => 'cmd-fail-1'],
            ],
            'attempt' => 0,
            'max_attempts' => 1,
            'status' => IntegrationWebhookDelivery::STATUS_PENDING,
            'next_attempt_at' => now(),
        ]);

        Http::fake([
            'receiver.invalid/*' => Http::response('downstream unavailable', 503),
        ]);

        $outcome = app(OutboundWebhookDeliveryService::class)->deliver($delivery->id);
        $this->assertFalse($outcome['retry']);

        $delivery->refresh();
        $endpoint->refresh();
        $this->assertSame(IntegrationWebhookDelivery::STATUS_DEAD_LETTER, $delivery->status);
        $this->assertSame('http_503', $delivery->last_error);
        $this->assertSame(IntegrationWebhookEndpoint::STATUS_FAILING, $endpoint->status);
    }
}

