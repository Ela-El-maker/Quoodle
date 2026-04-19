<?php

namespace App\Services\Integrations\Webhooks;

use App\Models\IntegrationWebhookDelivery;
use App\Models\IntegrationWebhookEndpoint;
use Illuminate\Support\Facades\Http;

final class OutboundWebhookDeliveryService
{
    /**
     * @return array{retry: bool, delay_seconds: int}
     */
    public function deliver(string $deliveryId): array
    {
        /** @var IntegrationWebhookDelivery|null $delivery */
        $delivery = IntegrationWebhookDelivery::query()->with('endpoint')->find($deliveryId);
        if (! $delivery) {
            return ['retry' => false, 'delay_seconds' => 0];
        }

        if (in_array($delivery->status, [IntegrationWebhookDelivery::STATUS_SENT, IntegrationWebhookDelivery::STATUS_DEAD_LETTER], true)) {
            return ['retry' => false, 'delay_seconds' => 0];
        }

        $endpoint = $delivery->endpoint;
        if (! $endpoint) {
            $delivery->update([
                'status' => IntegrationWebhookDelivery::STATUS_DEAD_LETTER,
                'last_error' => 'endpoint_not_found',
                'next_attempt_at' => null,
            ]);
            return ['retry' => false, 'delay_seconds' => 0];
        }

        if ($endpoint->status === IntegrationWebhookEndpoint::STATUS_PAUSED) {
            $delivery->update([
                'status' => IntegrationWebhookDelivery::STATUS_DEAD_LETTER,
                'last_error' => 'endpoint_paused',
                'next_attempt_at' => null,
            ]);
            return ['retry' => false, 'delay_seconds' => 0];
        }

        $attempt = (int) $delivery->attempt + 1;
        $delivery->attempt = $attempt;
        $delivery->status = IntegrationWebhookDelivery::STATUS_RETRYING;
        $delivery->sent_at = now();
        $delivery->save();

        $payload = is_array($delivery->payload_json) ? $delivery->payload_json : [];
        $rawBody = json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
        if (! is_string($rawBody)) {
            $delivery->update([
                'status' => IntegrationWebhookDelivery::STATUS_DEAD_LETTER,
                'last_error' => 'payload_encoding_failed',
                'next_attempt_at' => null,
            ]);
            return ['retry' => false, 'delay_seconds' => 0];
        }

        $timestamp = now()->toIso8601String();
        $eventId = (string) $delivery->event_id;
        $signature = $this->sign($timestamp, $eventId, $rawBody, (string) $endpoint->signing_secret_encrypted);

        $start = microtime(true);
        try {
            $response = Http::withBody($rawBody, 'application/json')
                ->withHeaders([
                    'Content-Type' => 'application/json',
                    'X-Quoodle-Signature' => $signature,
                    'X-Quoodle-Timestamp' => $timestamp,
                    'X-Quoodle-Event-Id' => $eventId,
                    'X-Quoodle-Delivery-Id' => (string) $delivery->id,
                ])
                ->timeout(max(1, ((int) $endpoint->timeout_ms) / 1000))
                ->send('POST', (string) $endpoint->url);

            $latencyMs = (int) round((microtime(true) - $start) * 1000);
            $body = substr((string) $response->body(), 0, 4000);

            if ($response->successful()) {
                $delivery->update([
                    'status' => IntegrationWebhookDelivery::STATUS_SENT,
                    'http_status' => $response->status(),
                    'latency_ms' => $latencyMs,
                    'response_body' => $body,
                    'last_error' => null,
                    'delivered_at' => now(),
                    'next_attempt_at' => null,
                ]);

                if ($endpoint->status === IntegrationWebhookEndpoint::STATUS_FAILING) {
                    $endpoint->update(['status' => IntegrationWebhookEndpoint::STATUS_ACTIVE]);
                }

                return ['retry' => false, 'delay_seconds' => 0];
            }

            return $this->markFailedAttempt($delivery, $endpoint, sprintf('http_%d', $response->status()), $response->status(), $latencyMs, $body);
        } catch (\Throwable $e) {
            $latencyMs = (int) round((microtime(true) - $start) * 1000);
            return $this->markFailedAttempt($delivery, $endpoint, (string) $e->getMessage(), null, $latencyMs, null);
        }
    }

    /**
     * @return array{retry: bool, delay_seconds: int}
     */
    private function markFailedAttempt(
        IntegrationWebhookDelivery $delivery,
        IntegrationWebhookEndpoint $endpoint,
        string $error,
        ?int $statusCode,
        ?int $latencyMs,
        ?string $responseBody,
    ): array {
        $attempt = (int) $delivery->attempt;
        $maxAttempts = max(1, (int) $delivery->max_attempts);
        $noRetry = $endpoint->retry_policy === IntegrationWebhookEndpoint::RETRY_NONE;
        $terminal = $noRetry || $attempt >= $maxAttempts;

        if ($terminal) {
            $delivery->update([
                'status' => IntegrationWebhookDelivery::STATUS_DEAD_LETTER,
                'http_status' => $statusCode,
                'latency_ms' => $latencyMs,
                'response_body' => $responseBody,
                'last_error' => $error,
                'next_attempt_at' => null,
            ]);

            $endpoint->update(['status' => IntegrationWebhookEndpoint::STATUS_FAILING]);

            return ['retry' => false, 'delay_seconds' => 0];
        }

        $delaySeconds = $this->nextDelaySeconds($endpoint->retry_policy, $attempt);
        $delivery->update([
            'status' => IntegrationWebhookDelivery::STATUS_RETRYING,
            'http_status' => $statusCode,
            'latency_ms' => $latencyMs,
            'response_body' => $responseBody,
            'last_error' => $error,
            'next_attempt_at' => now()->addSeconds($delaySeconds),
        ]);

        $endpoint->update(['status' => IntegrationWebhookEndpoint::STATUS_FAILING]);

        return ['retry' => true, 'delay_seconds' => $delaySeconds];
    }

    private function nextDelaySeconds(string $retryPolicy, int $attempt): int
    {
        return match ($retryPolicy) {
            IntegrationWebhookEndpoint::RETRY_LINEAR => 30,
            IntegrationWebhookEndpoint::RETRY_NONE => 0,
            default => min(300, (int) (pow(2, max(0, $attempt - 1))) + random_int(0, 3)),
        };
    }

    private function sign(string $timestamp, string $eventId, string $rawBody, string $secret): string
    {
        $canonical = $timestamp.'.'.$eventId.'.'.$rawBody;
        return hash_hmac('sha256', $canonical, $secret);
    }
}
