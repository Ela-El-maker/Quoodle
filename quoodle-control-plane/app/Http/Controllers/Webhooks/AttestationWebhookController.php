<?php

namespace App\Http\Controllers\Webhooks;

use App\Http\Controllers\Controller;
use App\Models\Device;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class AttestationWebhookController extends Controller
{
    public function store(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'device_id' => ['required', 'string'],
            'timestamp' => ['required', 'string'],
            'attestation' => ['required', 'array'],
        ]);

        if ($validator->fails()) {
            return response()->json(['status' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $data = $validator->validated();
        $device = Device::find($data['device_id']);
        if ($device) {
            $status = $data['attestation']['status'] ?? 'unknown';
            $device->update([
                'compliance_status' => $status === 'pass' ? 'compliant' : 'non_compliant',
                'last_seen' => $data['timestamp'],
            ]);
        }

        return response()->json(['status' => 'ack', 'action_required' => 'none']);
    }
}
