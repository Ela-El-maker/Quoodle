<?php

namespace App\Http\Controllers\Commands;

use App\Http\Controllers\Controller;
use App\Models\Command;
use App\Services\Commands\FastAPIDispatcher;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;

class CommandController extends Controller
{
    public function __construct(private readonly FastAPIDispatcher $dispatcher)
    {
    }

    public function store(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'client_message_id' => ['required', 'string', 'max:190'],
            'device_id' => ['required', 'string', 'max:190'],
            'method' => ['required', 'string', 'max:190'],
            'params' => ['required', 'array'],
            'sensitive' => ['required', 'boolean'],
            'two_factor_code' => ['nullable', 'string', 'max:190'],
        ]);

        if ($validator->fails()) {
            return response()->json([
                'status' => 'rejected',
                'reason' => 'validation_error',
                'errors' => $validator->errors(),
            ], 422);
        }

        $data = $validator->validated();

        $command = Command::create([
            'client_message_id' => $data['client_message_id'],
            'device_id' => $data['device_id'],
            'method' => $data['method'],
            'params' => $data['params'],
            'sensitive' => $data['sensitive'],
            'trace_id' => (string) Str::uuid(),
            'queued_at' => now(),
            'state' => 'queued',
            'status' => 'accepted',
        ]);

        $dispatchResult = $this->dispatcher->dispatch($command);

        $state = match ($dispatchResult['status'] ?? 'queued') {
            'dispatched' => 'sent',
            'device_offline' => 'queued',
            default => 'queued',
        };

        $command->update([
            'state' => $state,
            'dispatched_at' => $state === 'sent' ? now() : null,
            'reason' => $dispatchResult['reason'] ?? null,
        ]);

        return response()->json([
            'command_id' => $command->id,
            'queued_at' => $command->queued_at?->toIso8601String(),
            'reason' => $dispatchResult['reason'] ?? null,
            'state' => $state,
            'status' => 'accepted',
        ], 201);
    }
}
