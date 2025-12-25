<?php

namespace App\Http\Controllers\Telemetry;

use App\Http\Controllers\Controller;
use App\Models\TelemetrySnapshot;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class TelemetryController extends Controller
{
    public function latest(string $device_id): JsonResponse
    {
        $latest = TelemetrySnapshot::where('device_id', $device_id)->orderByDesc('timestamp')->first();

        return response()->json([
            'device_id' => $device_id,
            'timestamp' => optional($latest?->timestamp)?->toIso8601String(),
            'metrics' => $latest?->metrics ?? [
                'cpu' => null,
                'ram' => null,
                'disk_usage' => null,
                'network_tx' => null,
                'network_rx' => null,
                'risk_score' => null,
                'policy_hash' => null,
            ],
        ]);
    }

    public function history(Request $request, string $device_id): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'from' => ['required', 'date'],
            'to' => ['required', 'date'],
            'bucket' => ['required', 'string'],
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $data = $validator->validated();
        $points = TelemetrySnapshot::where('device_id', $device_id)
            ->whereBetween('timestamp', [$data['from'], $data['to']])
            ->orderBy('timestamp')
            ->get()
            ->map(function (TelemetrySnapshot $snap) {
                $metrics = $snap->metrics ?? [];

                return [
                    'timestamp' => optional($snap->timestamp)?->toIso8601String(),
                    'avg_cpu' => (float) ($metrics['cpu'] ?? 0),
                    'avg_ram' => (float) ($metrics['ram'] ?? 0),
                    'avg_disk_usage' => (float) ($metrics['disk_usage'] ?? 0),
                    'risk_score_avg' => (float) ($metrics['risk_score'] ?? 0),
                ];
            });

        return response()->json([
            'device_id' => $device_id,
            'bucket' => $data['bucket'],
            'points' => $points,
        ]);
    }
}
