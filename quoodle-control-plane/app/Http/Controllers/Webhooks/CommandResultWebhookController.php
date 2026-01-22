<?php

namespace App\Http\Controllers\Webhooks;

use App\Http\Controllers\Controller;
use App\Models\Command;
use App\Services\Webhooks\WebhookIdempotency;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class CommandResultWebhookController extends Controller
{
    public function __construct(private readonly WebhookIdempotency $idempotency)
    {
    }

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
            'event_id' => ['nullable', 'string'],
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

        if ($this->idempotency->isDuplicate('command_result', $data, $command->id)) {
            return response()->json(['status' => 'received', 'audit_id' => $data['trace_id'], 'idempotent' => true]);
        }

        $terminal = ['completed', 'failed', 'expired', 'rejected'];
        if (in_array($command->state, $terminal, true)) {
            return response()->json(['status' => 'received', 'audit_id' => $data['trace_id']]);
        }

        $executionState = $data['execution_state'];
        $state = match ($executionState) {
            'completed' => 'completed',
            'failed' => 'failed',
            'executing', 'partial' => 'executing',
            default => $command->state,
        };

        $update = [
            'state' => $state,
            'execution_state' => $executionState,
            'reason' => $data['error_message'] ?? null,
            'result' => $data['result'],
            'error_code' => $data['error_code'],
            'error_message' => $data['error_message'],
        ];

        if (in_array($state, ['completed', 'failed'], true)) {
            $update['completed_at'] = $data['timestamp'];
        }

        $command->update($update);

        return response()->json([
            'status' => 'received',
            'audit_id' => $data['trace_id'],
        ]);
    }
}
