<?php

namespace App\Http\Controllers\Commands;

use App\Http\Controllers\Controller;
use App\Services\Commands\CommandService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class CommandController extends Controller
{
    public function __construct(private readonly CommandService $commandService)
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
            'policy_hash' => ['nullable', 'string'],
            'user_id' => ['nullable', 'string'],
            'user_role' => ['nullable', 'string'],
            'attestation_status' => ['nullable', 'string'],
            'last_update_state' => ['nullable', 'string'],
            'clock_skew_seconds' => ['nullable', 'integer'],
        ]);

        if ($validator->fails()) {
            return response()->json([
                'status' => 'rejected',
                'reason' => 'validation_error',
                'errors' => $validator->errors(),
            ], 422);
        }

        $result = $this->commandService->enqueue($validator->validated());

        if ($result['status'] !== 'accepted') {
            return response()->json([
                'status' => $result['status'],
                'reason' => $result['reason'] ?? null,
                'policy' => $result['policy'] ?? null,
                'compliance' => $result['compliance'] ?? null,
                'errors' => $result['errors'] ?? null,
            ], $result['status'] === 'require_2fa' ? 403 : 422);
        }

        $command = $result['command'];

        return response()->json([
            'command_id' => $command->id,
            'queued_at' => $command->queued_at?->toIso8601String(),
            'reason' => $command->reason,
            'state' => $command->state,
            'status' => 'accepted',
            'policy' => $result['policy'],
            'compliance' => $result['compliance'],
        ], 201);
    }
}
