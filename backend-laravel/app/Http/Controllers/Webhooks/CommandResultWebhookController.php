<?php

namespace App\Http\Controllers\Webhooks;

use App\Http\Controllers\Controller;
use App\Models\Command;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class CommandResultWebhookController extends Controller
{
    public function store(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'command_id' => ['required', 'string'],
            'device_id' => ['required', 'string'],
            'trace_id' => ['required', 'string'],
            'execution_state' => ['required', 'string'],
            'result' => ['required', 'array'],
            'error_code' => ['nullable', 'integer'],
            'error_message' => ['nullable', 'string'],
            'timestamp' => ['required', 'string'],
        ]);

        if ($validator->fails()) {
            return response()->json([
                'status' => 'invalid',
                'errors' => $validator->errors(),
            ], 422);
        }

        $data = $validator->validated();

        $command = Command::find($data['command_id']);
        if (! $command) {
            return response()->json(['status' => 'unknown_command'], 404);
        }

        $state = $data['execution_state'] === 'completed' ? 'completed' : 'failed';
        $command->update([
            'state' => $state,
            'reason' => $data['error_message'] ?? null,
        ]);

        return response()->json([
            'status' => 'received',
            'audit_id' => $data['trace_id'],
        ]);
    }
}
