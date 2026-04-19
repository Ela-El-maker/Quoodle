<?php

namespace App\Services\Settings;

use App\Models\SettingsAuditEvent;
use App\Models\User;

class SettingsAuditService
{
    /**
     * @param  array<string,mixed>|null  $before
     * @param  array<string,mixed>|null  $after
     * @param  array<string,mixed>  $meta
     */
    public function record(
        ?User $actor,
        string $targetType,
        ?string $targetId,
        string $operation,
        ?array $before,
        ?array $after,
        array $meta = [],
    ): void {
        $beforeHash = $this->payloadHash($before);
        $afterHash = $this->payloadHash($after);

        SettingsAuditEvent::query()->create([
            'actor_user_id' => $actor?->id,
            'actor_email' => $actor?->email,
            'target_type' => $targetType,
            'target_id' => $targetId,
            'operation' => $operation,
            'before_hash' => $beforeHash,
            'after_hash' => $afterHash,
            'before_payload' => $before,
            'after_payload' => $after,
            'meta' => $meta === [] ? null : $meta,
            'occurred_at' => now(),
        ]);
    }

    /**
     * @param  array<string,mixed>|null  $payload
     */
    private function payloadHash(?array $payload): ?string
    {
        if ($payload === null) {
            return null;
        }

        $json = json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
        if (! is_string($json)) {
            return null;
        }

        return hash('sha256', $json);
    }
}

