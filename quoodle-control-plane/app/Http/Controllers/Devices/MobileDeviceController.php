<?php

namespace App\Http\Controllers\Devices;

use App\Http\Controllers\Controller;
use App\Models\MobileDevice;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Auth;

class MobileDeviceController extends Controller
{
    public function index(): JsonResponse
    {
        $user = Auth::user();
        if (! $user) {
            return response()->json(['status' => 'invalid_session'], 401);
        }

        $devices = MobileDevice::with(['links.device'])
            ->where('user_id', $user->id)
            ->orderByDesc('last_seen_at')
            ->get();

        return response()->json([
            'mobile_devices' => $devices->map(function (MobileDevice $device) {
                return [
                    'id' => $device->id,
                    'device_fingerprint' => $device->device_fingerprint,
                    'platform' => $device->platform,
                    'os_version' => $device->os_version,
                    'device_model' => $device->device_model,
                    'app_version' => $device->app_version,
                    'push_token' => $device->push_token,
                    'first_seen_at' => optional($device->first_seen_at)?->toIso8601String(),
                    'last_seen_at' => optional($device->last_seen_at)?->toIso8601String(),
                    'linked_devices' => $device->links->map(function ($link) {
                        return [
                            'device_id' => $link->device_id,
                            'device_name' => $link->device?->device_name,
                            'linked_at' => optional($link->linked_at)?->toIso8601String(),
                            'linked_via' => $link->linked_via,
                        ];
                    }),
                ];
            }),
        ]);
    }
}
