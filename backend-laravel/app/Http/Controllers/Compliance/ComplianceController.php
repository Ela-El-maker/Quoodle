<?php

namespace App\Http\Controllers\Compliance;

use App\Http\Controllers\Controller;
use App\Models\PolicyProfile;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class ComplianceController extends Controller
{
    public function profiles(): JsonResponse
    {
        $profiles = PolicyProfile::all(['profile_id', 'description', 'rules'])->map(function ($p) {
            return [
                'profile_id' => $p->profile_id,
                'description' => $p->description,
                'rules' => $p->rules ?? [],
            ];
        });

        return response()->json([
            'profiles' => $profiles,
        ]);
    }

    public function evaluate(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'agent_version' => ['required', 'string'],
            'attestation_status' => ['required', 'string'],
            'device_id' => ['required', 'string'],
            'last_update_state' => ['required', 'string'],
            'os_build' => ['required', 'string'],
            'policy_hash' => ['required', 'string'],
            'profile_id' => ['required', 'string'],
        ]);

        if ($validator->fails()) {
            return response()->json([
                'status' => 'unknown',
                'reasons' => $validator->errors()->all(),
            ], 422);
        }

        $data = $validator->validated();

        $reasons = [];
        $status = 'compliant';
        if ($data['attestation_status'] !== 'pass') {
            $status = 'non_compliant';
            $reasons[] = 'attestation_failed';
        }
        if ($data['last_update_state'] === 'failed') {
            $status = 'non_compliant';
            $reasons[] = 'update_failed';
        }

        return response()->json([
            'status' => $status,
            'reasons' => $reasons,
        ]);
    }
}
