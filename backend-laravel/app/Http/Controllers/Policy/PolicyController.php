<?php

namespace App\Http\Controllers\Policy;

use App\Http\Controllers\Controller;
use App\Models\Device;
use App\Services\CommandRegistry\Registry;
use App\Services\PolicyEngine\PolicyEvaluator;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class PolicyController extends Controller
{
    public function __construct(
        private readonly PolicyEvaluator $policyEvaluator,
        private readonly Registry $registry
    ) {
    }

    public function evaluate(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'device_id' => ['required', 'string'],
            'device_lifecycle_state' => ['required', 'string'],
            'method' => ['required', 'string'],
            'params' => ['required', 'array'],
            'policy_hash' => ['required', 'string'],
            'timestamp' => ['required', 'string'],
            'user_id' => ['required', 'string'],
            'user_role' => ['required', 'string'],
            'expected_policy_hash' => ['nullable', 'string'],
            'two_factor_verified' => ['nullable', 'boolean'],
        ]);

        if ($validator->fails()) {
            return response()->json([
                'decision' => 'deny',
                'reason' => 'validation_error',
                'errors' => $validator->errors(),
            ], 422);
        }

        $data = $validator->validated();

        $definition = $this->registry->get($data['method']);
        if (! $definition) {
            return response()->json([
                'decision' => 'deny',
                'reason' => 'unknown_command',
            ], 422);
        }

        $device = Device::find($data['device_id']);
        $policy = $this->policyEvaluator->evaluate([
            'user_id' => $data['user_id'],
            'user_role' => $data['user_role'],
            'device_lifecycle_state' => $data['device_lifecycle_state'],
            'policy_hash' => $data['policy_hash'],
            'expected_policy_hash' => $data['expected_policy_hash'] ?? $device?->policy_hash,
            'two_factor_verified' => $data['two_factor_verified'] ?? false,
        ], $definition, $device);

        return response()->json($policy);
    }

    public function validateBundle(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'policy_version' => ['required', 'string'],
            'rules' => ['required', 'array'],
            'signature' => ['required', 'string'],
        ]);

        if ($validator->fails()) {
            return response()->json([
                'status' => 'invalid',
                'errors' => $validator->errors()->all(),
            ], 422);
        }

        $rules = $validator->validated()['rules'];
        $unknownCommands = collect($rules['commands'] ?? [])
            ->reject(fn (array $rule) => $this->registry->get($rule['command'] ?? '') !== null)
            ->values()
            ->all();

        if (! empty($unknownCommands)) {
            return response()->json([
                'status' => 'invalid',
                'errors' => ['unknown_commands' => $unknownCommands],
            ], 422);
        }

        return response()->json([
            'status' => 'valid',
            'errors' => [],
        ]);
    }
}
