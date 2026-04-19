<?php

namespace App\Services\Integrations\Webhooks;

final class WebhookEventCatalog
{
    /**
     * @return array<int, string>
     */
    public static function all(): array
    {
        return [
            'command.queued',
            'command.ack',
            'command.completed',
            'command.failed',
            'device.online',
            'device.offline',
            'device.activated',
            'security.attestation.failed',
            'security.attestation.passed',
            'compliance.status.changed',
            'alert.critical',
        ];
    }

    public static function isSupported(string $eventType): bool
    {
        return in_array($eventType, self::all(), true);
    }
}
