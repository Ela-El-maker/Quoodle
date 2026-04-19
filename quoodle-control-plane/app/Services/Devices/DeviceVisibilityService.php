<?php

namespace App\Services\Devices;

use App\Models\Device;
use App\Models\TeamMemberDeviceAccess;
use App\Models\User;
use Illuminate\Database\Eloquent\Builder;

class DeviceVisibilityService
{
    public function visibleDevicesQuery(?User $user): Builder
    {
        $query = Device::query();

        if (! $user) {
            return $query->whereRaw('1 = 0');
        }

        if ($user->role === User::ROLE_ADMIN) {
            return $query;
        }

        $grantedDeviceIds = TeamMemberDeviceAccess::query()
            ->where('user_id', $user->id)
            ->pluck('device_id')
            ->filter(fn ($id) => is_string($id) && trim($id) !== '')
            ->values();

        return $query->where(function (Builder $where) use ($user, $grantedDeviceIds): void {
            $where->where('user_id', $user->id);
            if ($grantedDeviceIds->isNotEmpty()) {
                $where->orWhereIn('device_id', $grantedDeviceIds->all());
            }
        });
    }

    public function canViewDevice(?User $user, string $deviceId): bool
    {
        if (! $user) {
            return false;
        }

        return $this->visibleDevicesQuery($user)
            ->where('device_id', $deviceId)
            ->exists();
    }
}