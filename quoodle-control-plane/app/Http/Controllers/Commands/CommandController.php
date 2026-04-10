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
            // Commands like lock_screen legitimately have an empty params object.
            'params' => ['present', 'array'],
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

        $validated = $validator->validated();
        $user = $request->user();
        if ($user) {
            $validated['user_id'] = (string) $user->id;
            $validated['user_role'] = (string) ($user->role ?? 'viewer');
        } else {
            $validated['user_id'] = isset($validated['user_id']) ? (string) $validated['user_id'] : null;
            $validated['user_role'] = (string) ($validated['user_role'] ?? 'viewer');
        }

        $result = $this->commandService->enqueue($validated);

        if ($result['status'] !== 'accepted') {
            return response()->json([
                'status' => $result['status'],
                'reason' => $result['reason'] ?? null,
                'policy' => $result['policy'] ?? null,
                'compliance' => $result['compliance'] ?? null,
                'errors' => $result['errors'] ?? null,
            ], ($result['status'] === 'require_2fa' || ($result['reason'] ?? null) === 'invalid_2fa') ? 403 : 422);
        }

        $command = $result['command'];

        return response()->json([
            'command_id' => $command->id,
            'device_id' => $command->device_id,
            'method' => $command->method,
            'params' => $command->params ?? [],
            'queued_at' => $command->queued_at?->toIso8601String(),
            'completed_at' => $command->completed_at?->toIso8601String(),
            'reason' => $command->reason,
            'state' => $command->state,
            'status' => 'accepted',
            'policy' => $result['policy'],
            'compliance' => $result['compliance'],
        ], 201);
    }
}
