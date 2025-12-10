<?php

namespace App\Http\Controllers\Devices;

use App\Http\Controllers\Controller;
use App\Models\Device;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;

class PairingController extends Controller
{
    private const CACHE_PREFIX = 'pair_session_';

    public function init(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'device_label' => ['nullable', 'string', 'max:190'],
        ]);

        if ($validator->fails()) {
            return response()->json(['message' => 'validation_error', 'errors' => $validator->errors()], 422);
        }

        $pairSessionId = Str::uuid()->toString();
        $pairToken = Str::uuid()->toString();
        Cache::put(self::CACHE_PREFIX.$pairToken, [
            'pair_session_id' => $pairSessionId,
            'device_label' => $validator->validated()['device_label'] ?? null,
        ], now()->addMinutes(10));

        return response()->json([
            'pair_session_id' => $pairSessionId,
            'expires_at' => now()->addMinutes(10)->toIso8601String(),
            'qr_metadata' => [
                'info' => 'Scan with Windows Agent pairing QR',
            ],
            'pair_token' => $pairToken,
        ]);
    }

    public function confirm(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'pair_token' => ['required', 'string'],
            'pair_session_id' => ['nullable', 'string'],
        ]);

        if ($validator->fails()) {
            return response()->json(['status' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $data = $validator->validated();
        $cached = Cache::pull(self::CACHE_PREFIX.$data['pair_token']);

        if (! $cached) {
            return response()->json(['status' => 'expired', 'device_id' => null, 'device_name' => null, 'lifecycle_state' => null]);
        }

        $deviceId = Str::uuid()->toString();
        $device = Device::create([
            'device_id' => $deviceId,
            'device_name' => $cached['device_label'] ?? 'New Device',
            'lifecycle_state' => 'active',
            'compliance_status' => 'unknown',
        ]);

        return response()->json([
            'status' => 'ok',
            'device_id' => $device->device_id,
            'device_name' => $device->device_name,
            'lifecycle_state' => $device->lifecycle_state,
        ]);
    }
}
