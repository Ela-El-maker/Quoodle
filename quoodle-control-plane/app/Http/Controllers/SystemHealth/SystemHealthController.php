<?php

namespace App\Http\Controllers\SystemHealth;

use App\Http\Controllers\Controller;
use App\Services\SystemHealth\SystemHealthService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

final class SystemHealthController extends Controller
{
    public function __construct(private readonly SystemHealthService $health)
    {
    }

    public function overview(): JsonResponse
    {
        return response()->json($this->health->overview());
    }

    public function components(): JsonResponse
    {
        return response()->json([
            'generated_at' => now()->toIso8601String(),
            'components' => $this->health->components(),
        ]);
    }

    public function timeseries(Request $request): JsonResponse
    {
        $validator = Validator::make($request->query(), [
            'window_minutes' => ['nullable', 'integer', 'min:5', 'max:10080'],
            'bucket_minutes' => ['nullable', 'integer', 'min:1', 'max:60'],
        ]);

        if ($validator->fails()) {
            return response()->json(['message' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $data = $validator->validated();
        $windowMinutes = (int) ($data['window_minutes'] ?? 360);
        $bucketMinutes = (int) ($data['bucket_minutes'] ?? 5);

        return response()->json([
            'generated_at' => now()->toIso8601String(),
            'window_minutes' => $windowMinutes,
            'bucket_minutes' => $bucketMinutes,
            'points' => $this->health->timeseries($windowMinutes, $bucketMinutes),
        ]);
    }

    public function events(Request $request): JsonResponse
    {
        $validator = Validator::make($request->query(), [
            'limit' => ['nullable', 'integer', 'min:1', 'max:500'],
            'window_minutes' => ['nullable', 'integer', 'min:5', 'max:10080'],
        ]);

        if ($validator->fails()) {
            return response()->json(['message' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $validated = $validator->validated();
        $limit = (int) ($validated['limit'] ?? 100);
        $windowMinutes = (int) ($validated['window_minutes'] ?? 180);

        return response()->json([
            'generated_at' => now()->toIso8601String(),
            'window_minutes' => $windowMinutes,
            'events' => $this->health->events($limit, $windowMinutes),
        ]);
    }
}
