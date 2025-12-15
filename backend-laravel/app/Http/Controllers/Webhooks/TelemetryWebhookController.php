<?php

namespace App\Http\Controllers\Webhooks;

use App\Http\Controllers\Controller;
use App\Models\Device;
use App\Services\Telemetry\TelemetryIngestService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class TelemetryWebhookController extends Controller
{
    public function __construct(private readonly TelemetryIngestService $ingestService)
    {
    }

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
        if (! Device::find($data['device_id'])) {
            return response()->json(['status' => 'unknown_device'], 404);
        }
        $result = $this->ingestService->ingest($data['device_id'], $data);

        return response()->json(['status' => 'ok', 'snapshot' => $result]);
    }
}
