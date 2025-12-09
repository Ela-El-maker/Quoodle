<?php

namespace App\Http\Controllers\Audit;

use App\Http\Controllers\Controller;
use App\Models\AuditTrail;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class AuditTrailController extends Controller
{
    public function append(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'actor' => ['required', 'string'],
            'actor_id' => ['required', 'string'],
            'audit_id' => ['required', 'string'],
            'device_id' => ['nullable', 'string'],
            'event_type' => ['required', 'string'],
            'payload_hash' => ['required', 'string'],
            'prev_hash' => ['nullable', 'string'],
            'signature' => ['required', 'string'],
            'timestamp' => ['required', 'string'],
        ]);

        if ($validator->fails()) {
            return response()->json([
                'status' => 'invalid',
                'errors' => $validator->errors()->all(),
            ], 422);
        }

        $data = $validator->validated();

        $latest = AuditTrail::where('device_id', $data['device_id'])
            ->orderBy('timestamp', 'desc')
            ->first();
        $prevHash = $data['prev_hash'] ?? ($latest->hash ?? null);
        $computedHash = hash('sha256', ($prevHash ?? '') . $data['payload_hash']);

        $entry = AuditTrail::create([
            'audit_id' => $data['audit_id'],
            'actor' => $data['actor'],
            'actor_id' => $data['actor_id'],
            'device_id' => $data['device_id'],
            'event_type' => $data['event_type'],
            'payload_hash' => $data['payload_hash'],
            'prev_hash' => $prevHash,
            'hash' => $computedHash,
            'signature' => $data['signature'],
            'timestamp' => $data['timestamp'],
        ]);

        return response()->json([
            'status' => 'ok',
            'stored_hash' => $entry->hash,
        ]);
    }

    public function chain(string $device_id): JsonResponse
    {
        $entries = AuditTrail::where('device_id', $device_id)
            ->orderBy('timestamp')
            ->get(['audit_id', 'hash', 'prev_hash', 'signature as sig', 'timestamp']);

        return response()->json([
            'entries' => $entries,
        ]);
    }
}
