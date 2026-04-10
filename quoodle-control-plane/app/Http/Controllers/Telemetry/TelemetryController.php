<?php

namespace App\Http\Controllers\Telemetry;

use App\Http\Controllers\Controller;
use App\Models\DeviceTelemetryLatest;
use App\Models\TelemetryEvent;
use App\Models\TelemetrySnapshot;
use Illuminate\Support\Carbon;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class TelemetryController extends Controller
{
    public function latest(string $device_id): JsonResponse
    {
        $latest = DeviceTelemetryLatest::query()->where('device_id', $device_id)->first();
        if ($latest) {
            return response()->json([
                'device_id' => $device_id,
                'timestamp' => optional($latest->timestamp)?->toIso8601String(),
                'telemetry_scope' => $latest->telemetry_scope,
                'presence_state' => $latest->presence_state,
                'connection_mode' => $latest->connection_mode,
                'metrics' => $latest->metrics ?? [],
            ]);
        }

        $snapshot = TelemetrySnapshot::where('device_id', $device_id)->orderByDesc('timestamp')->first();

        return response()->json([
            'device_id' => $device_id,
            'timestamp' => optional($snapshot?->timestamp)?->toIso8601String(),
            'metrics' => $snapshot?->metrics ?? [
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
            'from' => ['nullable', 'date'],
            'to' => ['nullable', 'date'],
            'bucket' => ['nullable', 'string'],
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $data = $validator->validated();
        $to = isset($data['to']) ? Carbon::parse($data['to'])->utc() : now()->utc();
        $from = isset($data['from']) ? Carbon::parse($data['from'])->utc() : $to->copy()->subHours(24);
        if ($from->greaterThan($to)) {
            [$from, $to] = [$to->copy()->subHours(24), $to];
        }

        $events = TelemetryEvent::query()
            ->where('device_id', $device_id)
            ->whereBetween('timestamp', [$from, $to])
            ->orderBy('timestamp')
            ->limit(5000)
            ->get();

        if ($events->isNotEmpty()) {
            $points = $events->map(function (TelemetryEvent $event) {
                $metrics = $event->metrics ?? [];

                return [
                    'timestamp' => optional($event->timestamp)?->toIso8601String(),
                    'telemetry_scope' => $event->telemetry_scope,
                    'presence_state' => $event->presence_state,
                    'avg_cpu' => (float) ($metrics['cpu'] ?? 0),
                    'avg_ram' => (float) ($metrics['ram'] ?? 0),
                    'avg_disk_usage' => (float) ($metrics['disk_usage'] ?? 0),
                    'risk_score_avg' => (float) ($metrics['risk_score'] ?? 0),
                    'network_tx' => (float) ($metrics['network_tx'] ?? 0),
                    'network_rx' => (float) ($metrics['network_rx'] ?? 0),
                    'metrics' => $metrics,
                ];
            });
        } else {
            $points = TelemetrySnapshot::where('device_id', $device_id)
                ->whereBetween('timestamp', [$from, $to])
                ->orderBy('timestamp')
                ->limit(1000)
                ->get()
                ->map(function (TelemetrySnapshot $snap) {
                    $metrics = $snap->metrics ?? [];

                    return [
                        'timestamp' => optional($snap->timestamp)?->toIso8601String(),
                        'telemetry_scope' => null,
                        'presence_state' => null,
                        'avg_cpu' => (float) ($metrics['cpu'] ?? 0),
                        'avg_ram' => (float) ($metrics['ram'] ?? 0),
                        'avg_disk_usage' => (float) ($metrics['disk_usage'] ?? 0),
                        'risk_score_avg' => (float) ($metrics['risk_score'] ?? 0),
                        'network_tx' => (float) ($metrics['network_tx'] ?? 0),
                        'network_rx' => (float) ($metrics['network_rx'] ?? 0),
                        'metrics' => $metrics,
                    ];
                });
        }

        return response()->json([
            'device_id' => $device_id,
            'from' => $from->toIso8601String(),
            'to' => $to->toIso8601String(),
            'bucket' => $data['bucket'] ?? 'raw',
            'points' => $points,
        ]);
    }
}
