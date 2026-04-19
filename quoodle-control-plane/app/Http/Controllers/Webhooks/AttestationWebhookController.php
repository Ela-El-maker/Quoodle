<?php

namespace App\Http\Controllers\Webhooks;

use App\Http\Controllers\Controller;
use App\Models\Device;
use App\Services\Integrations\Webhooks\OutboundWebhookPublisher;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class AttestationWebhookController extends Controller
{
    public function __construct(private readonly OutboundWebhookPublisher $outboundWebhookPublisher)
    {
    }

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
            $previousComplianceStatus = (string) $device->compliance_status;
            $nextComplianceStatus = $status === 'pass' ? 'compliant' : 'non_compliant';
            $device->update([
                'compliance_status' => $nextComplianceStatus,
                'last_seen' => $data['timestamp'],
            ]);

            if ($status === 'pass') {
                $this->outboundWebhookPublisher->publish('security.attestation.passed', [
                    'device_id' => $device->device_id,
                    'device_name' => $device->device_name,
                    'timestamp' => $data['timestamp'],
                    'attestation' => $data['attestation'],
                ]);
            } elseif ($status === 'fail') {
                $this->outboundWebhookPublisher->publish('security.attestation.failed', [
                    'device_id' => $device->device_id,
                    'device_name' => $device->device_name,
                    'timestamp' => $data['timestamp'],
                    'attestation' => $data['attestation'],
                ]);
            }

            if ($previousComplianceStatus !== $nextComplianceStatus) {
                $this->outboundWebhookPublisher->publish('compliance.status.changed', [
                    'device_id' => $device->device_id,
                    'device_name' => $device->device_name,
                    'timestamp' => $data['timestamp'],
                    'previous_status' => $previousComplianceStatus,
                    'current_status' => $nextComplianceStatus,
                    'source' => 'attestation_webhook',
                ]);
            }
        }

        return response()->json(['status' => 'ack', 'action_required' => 'none']);
    }
}
