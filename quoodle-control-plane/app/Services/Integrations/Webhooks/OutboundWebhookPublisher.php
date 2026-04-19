<?php

namespace App\Services\Integrations\Webhooks;

use App\Jobs\DeliverIntegrationWebhookDelivery;
use App\Models\IntegrationWebhookDelivery;
use App\Models\IntegrationWebhookEndpoint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

final class OutboundWebhookPublisher
{
    public function publish(string $eventType, array $data): void
    {
        if (! WebhookEventCatalog::isSupported($eventType)) {
            return;
        }

        $eventId = (string) Str::ulid();
        $payload = [
            'event_type' => $eventType,
            'event_version' => 'v1',
            'event_id' => $eventId,
            'timestamp' => now()->toIso8601String(),
            'data' => $data,
        ];

        DB::afterCommit(function () use ($eventType, $eventId, $payload): void {
            $endpoints = IntegrationWebhookEndpoint::query()
                ->select('integration_webhook_endpoints.id', 'integration_webhook_endpoints.max_retries')
                ->join('integration_webhook_subscriptions as subscriptions', 'subscriptions.endpoint_id', '=', 'integration_webhook_endpoints.id')
                ->whereIn('integration_webhook_endpoints.status', [
                    IntegrationWebhookEndpoint::STATUS_ACTIVE,
                    IntegrationWebhookEndpoint::STATUS_FAILING,
                ])
                ->where('subscriptions.event_type', $eventType)
                ->distinct()
                ->get();

            foreach ($endpoints as $endpoint) {
                $endpointId = (string) $endpoint->id;

                $delivery = IntegrationWebhookDelivery::create([
                    'endpoint_id' => $endpointId,
                    'event_type' => $eventType,
                    'event_id' => $eventId,
                    'payload_json' => $payload,
                    'attempt' => 0,
                    'max_attempts' => max(1, ((int) $endpoint->max_retries) + 1),
                    'status' => IntegrationWebhookDelivery::STATUS_PENDING,
                    'next_attempt_at' => now(),
                ]);

                DeliverIntegrationWebhookDelivery::dispatch($delivery->id);
            }
        });
    }

    public function enqueueForEndpoint(IntegrationWebhookEndpoint $endpoint, string $eventType, array $data): IntegrationWebhookDelivery
    {
        $eventId = (string) Str::ulid();

        $payload = [
            'event_type' => $eventType,
            'event_version' => 'v1',
            'event_id' => $eventId,
            'timestamp' => now()->toIso8601String(),
            'data' => $data,
        ];

        $delivery = IntegrationWebhookDelivery::create([
            'endpoint_id' => $endpoint->id,
            'event_type' => $eventType,
            'event_id' => $eventId,
            'payload_json' => $payload,
            'attempt' => 0,
            'max_attempts' => $this->maxAttemptsForEndpoint($endpoint),
            'status' => IntegrationWebhookDelivery::STATUS_PENDING,
            'next_attempt_at' => now(),
        ]);

        DB::afterCommit(fn () => DeliverIntegrationWebhookDelivery::dispatch($delivery->id));

        return $delivery;
    }

    private function maxAttemptsForEndpoint(IntegrationWebhookEndpoint $endpoint): int
    {
        // max_retries counts retries after the initial attempt.
        return max(1, (int) $endpoint->max_retries + 1);
    }
}
