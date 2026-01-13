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

    public int $tries = 5;

    public function handle(FastAPIDispatcher $dispatcher): void
    {
        $command = Command::find($this->commandId);
        if (! $command) {
            return;
        }

        $result = $dispatcher->dispatch($command, $this->policy, $this->compliance);

        $state = match ($result['status'] ?? 'queued') {
            'dispatched', 'queued' => 'sent',
            'device_offline' => 'queued',
            default => 'queued',
        };

        $command->update([
            'state' => $state,
            'execution_state' => $state,
            'dispatched_at' => $state === 'sent' ? now() : null,
            'reason' => $result['reason'] ?? null,
        ]);
    }
}
