<?php

namespace App\Http\Controllers\Policy;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class PolicyController extends Controller
{
    public function evaluate(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'command_risk_level' => ['required', 'string'],
            'device_id' => ['required', 'string'],
            'device_lifecycle_state' => ['required', 'string'],
            'method' => ['required', 'string'],
            'params' => ['required', 'array'],
            'policy_hash' => ['required', 'string'],
            'timestamp' => ['required', 'string'],
            'user_id' => ['required', 'string'],
            'user_role' => ['required', 'string'],
        ]);

        if ($validator->fails()) {
            return response()->json([
                'decision' => 'deny',
                'reason' => 'validation_error',
                'errors' => $validator->errors(),
            ], 422);
        }

        $data = $validator->validated();
        $risk = strtolower($data['command_risk_level']);

        $decision = 'allow';
        $reason = 'ok';
        if ($risk === 'high') {
            $decision = 'require_2fa';
            $reason = 'high_risk_command';
        } elseif ($data['device_lifecycle_state'] === 'quarantine') {
            $decision = 'deny';
            $reason = 'device_quarantined';
        }

        return response()->json([
            'decision' => $decision,
            'reason' => $reason,
        ]);
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

        return response()->json([
            'status' => 'valid',
            'errors' => [],
        ]);
    }
}
