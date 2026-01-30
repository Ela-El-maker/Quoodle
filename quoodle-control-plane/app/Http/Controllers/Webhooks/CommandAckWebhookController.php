<?php

namespace App\Http\Controllers\Webhooks;

use App\Http\Controllers\Controller;
use App\Models\Command;
use App\Services\Webhooks\WebhookIdempotency;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class CommandAckWebhookController extends Controller
{
    public function __construct(private readonly WebhookIdempotency $idempotency)
    {
    }

    public function store(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'command_id' => ['required', 'string'],
            'device_id' => ['required', 'string'],
            'status' => ['required', 'string'],
            'reason' => ['nullable', 'string'],
            'timestamp' => ['required', 'string'],
            'event_id' => ['nullable', 'string'],
        ]);

        if ($validator->fails()) {
            return response()->json(['status' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $data = $validator->validated();
        $command = Command::find($data['command_id']);
        if (! $command) {
            return response()->json(['status' => 'unknown_command'], 404);
        }

        if ($this->idempotency->isDuplicate('command_ack', $data, $command->id)) {
            return response()->json(['status' => 'ok', 'idempotent' => true]);
        }

        $terminal = ['completed', 'failed', 'expired', 'rejected'];
        if (in_array($command->state, $terminal, true)) {
            return response()->json(['status' => 'ok']);
        }
        if (in_array($command->execution_state, ['completed', 'failed', 'expired'], true)) {
            return response()->json(['status' => 'ok']);
        }

        if ($data['status'] === 'received') {
            $updated = Command::where('id', $command->id)
                ->whereIn('state', ['queued', 'dispatched', 'sent'])
                ->whereNotIn('execution_state', ['completed', 'failed', 'expired'])
                ->update([
                    'state' => 'ack_received',
                    'reason' => $data['reason'] ?? null,
                ]);
            if ($updated < 1) {
                return response()->json(['status' => 'ok']);
            }
        } else {
            $command->update([
                'state' => 'failed',
                'execution_state' => 'failed',
                'reason' => $data['reason'] ?? null,
                'completed_at' => $data['timestamp'],
            ]);
        }

        return response()->json(['status' => 'ok']);
    }
}
