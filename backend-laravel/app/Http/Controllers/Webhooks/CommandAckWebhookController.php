<?php

namespace App\Http\Controllers\Webhooks;

use App\Http\Controllers\Controller;
use App\Models\Command;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class CommandAckWebhookController extends Controller
{
    public function store(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'command_id' => ['required', 'string'],
            'device_id' => ['required', 'string'],
            'status' => ['required', 'string'],
            'reason' => ['nullable', 'string'],
            'timestamp' => ['required', 'string'],
        ]);

        if ($validator->fails()) {
            return response()->json(['status' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $data = $validator->validated();
        $command = Command::find($data['command_id']);
        if (! $command) {
            return response()->json(['status' => 'unknown_command'], 404);
        }

        $command->update([
            'state' => $data['status'] === 'received' ? 'ack_received' : 'failed',
            'reason' => $data['reason'] ?? null,
        ]);

        return response()->json(['status' => 'ok']);
    }
}
