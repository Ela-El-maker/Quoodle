<?php

namespace App\Http\Controllers\Integrations;

use App\Http\Controllers\Controller;
use App\Jobs\DeliverIntegrationWebhookDelivery;
use App\Models\IntegrationWebhookDelivery;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;

final class WebhookDeliveryController extends Controller
{
    public function inbound(Request $request): JsonResponse
    {
        $validator = Validator::make($request->query(), [
            'event_type' => ['nullable', 'string', 'max:64'],
            'limit' => ['nullable', 'integer', 'min:1', 'max:500'],
        ]);

        if ($validator->fails()) {
            return response()->json(['message' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $filters = $validator->validated();
        $limit = (int) ($filters['limit'] ?? 200);

        $query = DB::table('processed_webhook_events')
            ->select([
                'id',
                'event_key',
                'event_type',
                'command_id',
                'received_at',
                'created_at',
            ])
            ->orderByDesc('received_at');

        if (! empty($filters['event_type'])) {
            $query->where('event_type', $filters['event_type']);
        }

        $events = $query->limit($limit)->get();

        $statsQuery = DB::table('processed_webhook_events')
            ->where('received_at', '>=', now()->subDay());
        if (! empty($filters['event_type'])) {
            $statsQuery->where('event_type', $filters['event_type']);
        }
        $last24h = (int) $statsQuery->count();

        $byType = DB::table('processed_webhook_events')
            ->select(['event_type', DB::raw('COUNT(*) as total')])
            ->groupBy('event_type')
            ->orderByDesc('total')
            ->limit(20)
            ->get();

        return response()->json([
            'events' => $events,
            'stats' => [
                'last_24h' => $last24h,
                'total_shown' => $events->count(),
            ],
            'event_breakdown' => $byType,
        ]);
    }

    public function index(Request $request): JsonResponse
    {
        $limit = min(max((int) $request->query('limit', 200), 1), 500);

        $validator = Validator::make($request->query(), [
            'endpoint_id' => ['nullable', 'string'],
            'status' => ['nullable', Rule::in([
                IntegrationWebhookDelivery::STATUS_PENDING,
                IntegrationWebhookDelivery::STATUS_RETRYING,
                IntegrationWebhookDelivery::STATUS_SENT,
                IntegrationWebhookDelivery::STATUS_DEAD_LETTER,
            ])],
            'event_type' => ['nullable', 'string'],
        ]);

        if ($validator->fails()) {
            return response()->json(['message' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $filters = $validator->validated();
        $query = IntegrationWebhookDelivery::query()
            ->with('endpoint:id,name,url,created_by')
            ->orderByDesc('created_at');

        if (! empty($filters['endpoint_id'])) {
            $query->where('endpoint_id', $filters['endpoint_id']);
        }
        if (! empty($filters['status'])) {
            $query->where('status', $filters['status']);
        }
        if (! empty($filters['event_type'])) {
            $query->where('event_type', $filters['event_type']);
        }

        $deliveries = $query->limit($limit)->get();

        return response()->json([
            'deliveries' => $deliveries->map(fn (IntegrationWebhookDelivery $delivery) => $this->serializeDelivery($delivery, $request)),
        ]);
    }

    public function replay(Request $request, string $id): JsonResponse
    {
        $user = $request->user();
        $source = IntegrationWebhookDelivery::query()->with('endpoint')->find($id);
        if (! $source) {
            return response()->json(['message' => 'not_found'], 404);
        }

        if (! $source->endpoint) {
            return response()->json(['message' => 'endpoint_not_found'], 404);
        }

        if (! $this->canManage($user?->role ?? '', (string) ($user?->id ?? ''), (string) $source->endpoint->created_by)) {
            return response()->json(['message' => 'forbidden'], 403);
        }

        $payload = is_array($source->payload_json) ? $source->payload_json : [];
        $payload['event_id'] = (string) Str::ulid();
        $payload['timestamp'] = now()->toIso8601String();
        $payload['replay_of_event_id'] = $source->event_id;

        $delivery = IntegrationWebhookDelivery::create([
            'endpoint_id' => $source->endpoint_id,
            'event_type' => $source->event_type,
            'event_id' => (string) $payload['event_id'],
            'payload_json' => $payload,
            'attempt' => 0,
            'max_attempts' => max(1, ((int) $source->endpoint->max_retries) + 1),
            'status' => IntegrationWebhookDelivery::STATUS_PENDING,
            'next_attempt_at' => now(),
            'replayed_from_delivery_id' => $source->id,
        ]);

        DeliverIntegrationWebhookDelivery::dispatch($delivery->id);

        return response()->json([
            'status' => 'queued',
            'delivery_id' => $delivery->id,
        ]);
    }

    private function canManage(string $role, string $userId, string $ownerUserId): bool
    {
        if ($role === 'admin') {
            return true;
        }

        return $role === 'operator' && $userId !== '' && $ownerUserId === $userId;
    }

    private function serializeDelivery(IntegrationWebhookDelivery $delivery, Request $request): array
    {
        $user = $request->user();
        $ownerUserId = (string) ($delivery->endpoint?->created_by ?? '');

        return [
            'id' => $delivery->id,
            'endpoint_id' => $delivery->endpoint_id,
            'endpoint_name' => $delivery->endpoint?->name,
            'event_type' => $delivery->event_type,
            'event_id' => $delivery->event_id,
            'status' => $delivery->status,
            'attempt' => $delivery->attempt,
            'max_attempts' => $delivery->max_attempts,
            'next_attempt_at' => $delivery->next_attempt_at?->toIso8601String(),
            'http_status' => $delivery->http_status,
            'latency_ms' => $delivery->latency_ms,
            'response_body' => $delivery->response_body,
            'last_error' => $delivery->last_error,
            'sent_at' => $delivery->sent_at?->toIso8601String(),
            'delivered_at' => $delivery->delivered_at?->toIso8601String(),
            'created_at' => $delivery->created_at?->toIso8601String(),
            'replayed_from_delivery_id' => $delivery->replayed_from_delivery_id,
            'payload' => $delivery->payload_json,
            'can_replay' => $this->canManage((string) ($user?->role ?? ''), (string) ($user?->id ?? ''), $ownerUserId),
        ];
    }
}
