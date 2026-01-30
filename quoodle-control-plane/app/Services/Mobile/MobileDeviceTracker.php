<?php

namespace App\Services\Mobile;

use App\Models\MobileDevice;
use App\Models\User;

class MobileDeviceTracker
{
    public function touch(User $user, array $payload): ?MobileDevice
    {
        $fingerprint = $payload['device_fingerprint'] ?? null;
        if (! $fingerprint) {
            return null;
        }

        $device = MobileDevice::firstOrNew([
            'user_id' => $user->id,
            'device_fingerprint' => $fingerprint,
        ]);

        if (! $device->exists) {
            $device->first_seen_at = now();
        }

        $device->platform = $payload['platform'] ?? $device->platform;
        $device->os_version = $payload['os_version'] ?? $device->os_version;
        $device->device_model = $payload['device_model'] ?? $device->device_model;
        $device->app_version = $payload['app_version'] ?? $device->app_version;
        $device->push_token = $payload['push_token'] ?? $device->push_token;
        $device->last_seen_at = now();

        $device->save();

        return $device;
    }
}
