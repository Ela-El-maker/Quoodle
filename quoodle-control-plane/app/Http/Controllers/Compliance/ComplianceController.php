<?php

namespace App\Http\Controllers\Compliance;

use App\Http\Controllers\Controller;
use App\Models\Device;
use App\Models\PolicyProfile;
use App\Services\Compliance\ComplianceChecker;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class ComplianceController extends Controller
{
    public function __construct(private readonly ComplianceChecker $complianceChecker)
    {
    }

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
            'revocation_status' => ['nullable', 'string'],
            'clock_skew_seconds' => ['nullable', 'integer'],
        ]);

        if ($validator->fails()) {
            return response()->json([
                'status' => 'unknown',
                'reasons' => $validator->errors()->all(),
            ], 422);
        }

        $data = $validator->validated();
        $device = Device::find($data['device_id']);
        if (! $device) {
            return response()->json(['status' => 'unknown_device'], 404);
        }

        $result = $this->complianceChecker->evaluateDevice($device, [
            'attestation_status' => $data['attestation_status'],
            'last_update_state' => $data['last_update_state'],
            'policy_hash' => $data['policy_hash'],
            'expected_policy_hash' => $device->policy_hash,
            'revocation_status' => $data['revocation_status'] ?? 'ok',
            'clock_skew_seconds' => $data['clock_skew_seconds'] ?? 0,
        ]);

        $device->update([
            'compliance_status' => $result['status'],
            'risk_score' => $device->risk_score,
        ]);

        return response()->json($result);
    }
}
