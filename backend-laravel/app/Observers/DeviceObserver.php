<?php

namespace App\Observers;

use App\Jobs\SyncDeviceKeyToFastApi;
use App\Models\Device;

final class DeviceObserver
{
    public function saved(Device $device): void
    {
        // Only sync when the public key becomes available or changes.
        if ($device->wasChanged('ed25519_pubkey_b64') && ! empty($device->ed25519_pubkey_b64)) {
            SyncDeviceKeyToFastApi::dispatch($device->device_id);
        }
    }
}
