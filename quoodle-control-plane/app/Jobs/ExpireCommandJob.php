<?php

namespace App\Jobs;

use App\Models\Command;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;

final class ExpireCommandJob implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public function __construct(public string $commandId)
    {
        $this->onQueue('commands');
    }

    public function handle(): void
    {
        $command = Command::find($this->commandId);
        if (! $command) {
            return;
        }

        if (in_array($command->state, ['completed', 'failed', 'expired', 'rejected'], true)) {
            return;
        }

        $expiresAt = $command->expires_at;
        if (! $expiresAt || now()->lessThan($expiresAt)) {
            return;
        }

        $command->update([
            'state' => 'expired',
            'execution_state' => 'expired',
            'reason' => $command->reason ?: 'ttl_expired',
            'completed_at' => now(),
        ]);
    }
}
