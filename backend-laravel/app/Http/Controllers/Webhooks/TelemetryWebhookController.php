<?php

namespace App\Http\Controllers\Webhooks;

use App\Http\Controllers\Controller;
use App\Models\TelemetrySnapshot;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class TelemetryWebhookController extends Controller
{
    public function store(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'device_id' => ['required', 'string'],
            'timestamp' => ['required', 'string'],
            'rollup' => ['required', 'array'],
        ]);

        if ($validator->fails()) {
            return response()->json(['status' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $data = $validator->validated();
        TelemetrySnapshot::create([
            'device_id' => $data['device_id'],
            'timestamp' => $data['timestamp'],
            'metrics' => [
                'cpu' => $data['rollup']['avg_cpu'] ?? null,
                'ram' => $data['rollup']['avg_ram'] ?? null,
                'disk_usage' => $data['rollup']['avg_disk'] ?? null,
                'network_tx' => null,
                'network_rx' => null,
                'risk_score' => $data['rollup']['risk_score_avg'] ?? null,
            ],
        ]);

        return response()->json(['status' => 'ok']);
    }
}
