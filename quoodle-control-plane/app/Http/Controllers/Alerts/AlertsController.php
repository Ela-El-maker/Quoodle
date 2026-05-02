<?php

namespace App\Http\Controllers\Alerts;

use App\Http\Controllers\Controller;
use App\Models\Alert;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class AlertsController extends Controller
{
    public function index(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'severity' => ['nullable', 'string'],
            'status' => ['nullable', 'string'],
            'device_id' => ['nullable', 'string'],
            'q' => ['nullable', 'string'],
            'limit' => ['nullable', 'integer'],
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $filters = $validator->validated();
        $query = Alert::query()->orderByDesc('timestamp');

        if (! empty($filters['severity'])) {
            $query->where('severity', $filters['severity']);
        }
        $status = strtolower(trim((string) ($filters['status'] ?? 'all')));
        if ($status === 'active') {
            $query->where('acknowledged', false);
        } elseif ($status === 'acknowledged') {
            $query->where('acknowledged', true);
        }

        if (! empty($filters['device_id'])) {
            $query->where('device_id', $filters['device_id']);
        }

        $q = trim((string) ($filters['q'] ?? ''));
        if ($q !== '') {
            $query->where(function ($search) use ($q): void {
                $search->where('alert_id', 'like', '%'.$q.'%')
                    ->orWhere('device_id', 'like', '%'.$q.'%')
                    ->orWhere('category', 'like', '%'.$q.'%')
                    ->orWhere('message', 'like', '%'.$q.'%');
            });
        }

        $alerts = $query->limit(min($filters['limit'] ?? 20, 200))->get();

        return response()->json([
            'alerts' => $alerts->map(function (Alert $alert) {
                $status = $alert->acknowledged ? 'acknowledged' : 'active';
                return [
                    'alert_id' => $alert->alert_id,
                    'device_id' => $alert->device_id,
                    'severity' => $alert->severity,
                    'category' => $alert->category,
                    'message' => $alert->message,
                    'timestamp' => optional($alert->timestamp)?->toIso8601String(),
                    'acknowledged' => $alert->acknowledged,
                    'status' => $status,
                ];
            }),
        ]);
    }

    public function acknowledge(string $alert_id): JsonResponse
    {
        $alert = Alert::where('alert_id', $alert_id)->first();
        if (! $alert) {
            return response()->json(['message' => 'not_found'], 404);
        }

        $alert->update(['acknowledged' => true]);

        return response()->json([
            'status' => 'ok',
            'alert_id' => $alert_id,
            'acknowledged_at' => now()->toIso8601String(),
        ]);
    }
}
