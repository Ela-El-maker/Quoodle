<?php

namespace App\Http\Controllers\Updates;

use App\Http\Controllers\Controller;
use App\Models\DeviceUpdate;
use Illuminate\Http\JsonResponse;

class UpdateController extends Controller
{
    public function list(string $device_id): JsonResponse
    {
        $updates = DeviceUpdate::where('device_id', $device_id)->orderByDesc('last_update_at')->get();

        return response()->json([
            'device_id' => $device_id,
            'updates' => $updates->map(function (DeviceUpdate $update) {
                return [
                    'release_id' => $update->release_id,
                    'version' => $update->version,
                    'status' => $update->phase,
                    'last_update_at' => optional($update->last_update_at)?->toIso8601String(),
                    'rollback_available' => (bool) $update->rollback_snapshot_id,
                ];
            }),
        ]);
    }

    public function show(string $device_id, string $release_id): JsonResponse
    {
        $update = DeviceUpdate::where('device_id', $device_id)->where('release_id', $release_id)->first();
        if (! $update) {
            return response()->json(['message' => 'not_found'], 404);
        }

        return response()->json([
            'device_id' => $device_id,
            'release_id' => $release_id,
            'version' => $update->version,
            'phase' => $update->phase,
            'progress' => [
                'percent' => $update->progress_percent,
                'detail' => $update->progress_detail,
            ],
            'error_code' => $update->error_code,
            'error_message' => $update->error_message,
            'rollback_snapshot_id' => $update->rollback_snapshot_id,
        ]);
    }
}
