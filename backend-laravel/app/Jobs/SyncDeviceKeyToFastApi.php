<?php

namespace App\Jobs;

use App\Models\Device;
use App\Services\Devices\FastApiDeviceKeySync;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;

final class SyncDeviceKeyToFastApi implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public function __construct(public string $deviceId)
    {
        $this->onQueue('fastapi');
    }

    public int $tries = 5;

    public function handle(FastApiDeviceKeySync $sync): void
    {
        $device = Device::find($this->deviceId);
        if (! $device) {
            return;
        }

        $sync->push($device);
    }
}
