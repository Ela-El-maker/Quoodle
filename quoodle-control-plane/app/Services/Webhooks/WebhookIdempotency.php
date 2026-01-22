<?php

namespace App\Services\Webhooks;

use App\Services\Security\Ed25519CanonicalJson;
use Illuminate\Support\Facades\DB;
use Illuminate\Database\QueryException;

final class WebhookIdempotency
{
    /**
     * Returns true if this webhook payload was already processed.
     */
    public function isDuplicate(string $eventType, array $payload, ?string $commandId = null): bool
    {
        $eventId = $payload['event_id'] ?? null;
        $eventKey = is_string($eventId) && $eventId !== ''
            ? $eventId
            : hash('sha256', Ed25519CanonicalJson::encode($payload));

        try {
            DB::table('processed_webhook_events')->insert([
                'event_key' => $eventKey,
                'event_type' => $eventType,
                'command_id' => $commandId,
                'received_at' => now(),
                'created_at' => now(),
                'updated_at' => now(),
            ]);
        } catch (QueryException $e) {
            // Duplicate key -> already processed.
            return true;
        }

        return false;
    }
}
