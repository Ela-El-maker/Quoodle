<?php

namespace App\Jobs;

use App\Models\Command;
use App\Services\Commands\FastAPIDispatcher;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;

final class DispatchCommandToFastApi implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    /**
     * @param  array<string,mixed>  $policy
     * @param  array<string,mixed>  $compliance
     */
    public function __construct(
        public string $commandId,
        public array $policy,
        public array $compliance,
    ) {
        $this->onQueue('fastapi');
    }

    public int $tries = 120;

    public function handle(FastAPIDispatcher $dispatcher): void
    {
        $command = Command::find($this->commandId);
        if (! $command) {
            return;
        }

        $result = $dispatcher->dispatch($command, $this->policy, $this->compliance);

        $status = $result['status'] ?? 'queued';
        if ($status === 'queued_offline') {
            $command->update([
                'state' => 'queued',
                'execution_state' => 'queued',
                'dispatched_at' => null,
                'reason' => $result['reason'] ?? 'device not connected',
            ]);

            $expiresAt = $command->expires_at;
            if ($expiresAt && now()->lt($expiresAt)) {
                // Retry until command TTL expires so transient reconnects do not strand queue rows.
                $this->release(5);
            }

            return;
        }

        $state = match ($status) {
            'dispatched' => 'dispatched',
            'queued', 'queued_offline' => 'queued',
            'blocked' => 'rejected',
            default => 'queued',
        };

        $command->update([
            'state' => $state,
            'execution_state' => $state,
            'dispatched_at' => $state === 'dispatched' ? now() : null,
            'reason' => $result['reason'] ?? ($status === 'blocked' ? 'device_quarantined' : null),
        ]);
    }
}
