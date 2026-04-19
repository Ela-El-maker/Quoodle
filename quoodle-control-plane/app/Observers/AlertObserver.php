<?php

namespace App\Observers;

use App\Models\Alert;
use App\Services\Integrations\Webhooks\OutboundWebhookPublisher;

final class AlertObserver
{
    public function __construct(private readonly OutboundWebhookPublisher $outboundWebhookPublisher)
    {
    }

    public function created(Alert $alert): void
    {
        if (strtolower((string) $alert->severity) !== 'critical') {
            return;
        }

        $this->outboundWebhookPublisher->publish('alert.critical', [
            'alert_id' => $alert->alert_id,
            'device_id' => $alert->device_id,
            'severity' => $alert->severity,
            'category' => $alert->category,
            'message' => $alert->message,
            'timestamp' => $alert->timestamp?->toIso8601String(),
            'acknowledged' => (bool) $alert->acknowledged,
        ]);
    }
}

