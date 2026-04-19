<?php

namespace App\Jobs;

use App\Services\Integrations\Webhooks\OutboundWebhookDeliveryService;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;

final class DeliverIntegrationWebhookDelivery implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public int $tries = 1;

    public function __construct(public string $deliveryId)
    {
        $this->onQueue('webhooks');
    }

    public function handle(OutboundWebhookDeliveryService $service): void
    {
        $outcome = $service->deliver($this->deliveryId);

        if (($outcome['retry'] ?? false) === true) {
            $delay = max(1, (int) ($outcome['delay_seconds'] ?? 1));
            self::dispatch($this->deliveryId)->delay(now()->addSeconds($delay));
        }
    }
}
