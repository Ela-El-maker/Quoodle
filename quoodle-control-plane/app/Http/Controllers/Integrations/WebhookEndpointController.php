<?php

namespace App\Http\Controllers\Integrations;

use App\Http\Controllers\Controller;
use App\Models\IntegrationWebhookDelivery;
use App\Models\IntegrationWebhookEndpoint;
use App\Services\Integrations\Webhooks\OutboundWebhookPublisher;
use App\Services\Integrations\Webhooks\WebhookEventCatalog;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Str;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\Rule;

final class WebhookEndpointController extends Controller
{
    public function __construct(private readonly OutboundWebhookPublisher $publisher)
    {
    }

    public function index(Request $request): JsonResponse
    {
        $user = $request->user();

        $endpoints = IntegrationWebhookEndpoint::query()
            ->with([
                'subscriptions:id,endpoint_id,event_type',
                'latestDelivery',
                'creator:id,email',
            ])
            ->withCount([
                'deliveries as success_count' => fn ($q) => $q->where('status', IntegrationWebhookDelivery::STATUS_SENT),
                'deliveries as dead_letter_count' => fn ($q) => $q->where('status', IntegrationWebhookDelivery::STATUS_DEAD_LETTER),
                'deliveries as retrying_count' => fn ($q) => $q->where('status', IntegrationWebhookDelivery::STATUS_RETRYING),
            ])
            ->orderByDesc('created_at')
            ->get();

        return response()->json([
            'endpoints' => $endpoints->map(fn (IntegrationWebhookEndpoint $endpoint) => $this->serializeEndpoint($endpoint, $user, false)),
            'event_catalog' => WebhookEventCatalog::all(),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $user = $request->user();
        if (! $user) {
            return response()->json(['message' => 'unauthenticated'], 401);
        }

        $validator = Validator::make($request->all(), [
            'name' => ['required', 'string', 'max:190'],
            'url' => ['required', 'url', 'max:2048'],
            'events' => ['required', 'array', 'min:1'],
            'events.*' => ['required', 'string', Rule::in(WebhookEventCatalog::all())],
            'retry_policy' => ['nullable', Rule::in([
                IntegrationWebhookEndpoint::RETRY_EXPONENTIAL,
                IntegrationWebhookEndpoint::RETRY_LINEAR,
                IntegrationWebhookEndpoint::RETRY_NONE,
            ])],
            'max_retries' => ['nullable', 'integer', 'min:0', 'max:10'],
            'timeout_ms' => ['nullable', 'integer', 'min:500', 'max:30000'],
        ]);

        if ($validator->fails()) {
            return response()->json(['message' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $data = $validator->validated();
        $secret = $this->generateSecret();

        $endpoint = IntegrationWebhookEndpoint::create([
            'name' => $data['name'],
            'url' => $data['url'],
            'status' => IntegrationWebhookEndpoint::STATUS_ACTIVE,
            'signing_algo' => 'hmac-sha256',
            'retry_policy' => $data['retry_policy'] ?? IntegrationWebhookEndpoint::RETRY_EXPONENTIAL,
            'max_retries' => (int) ($data['max_retries'] ?? 3),
            'timeout_ms' => (int) ($data['timeout_ms'] ?? 5000),
            'signing_secret_encrypted' => $secret,
            'created_by' => $user->id,
            'updated_by' => $user->id,
        ]);

        $this->syncSubscriptions($endpoint, $data['events']);
        $endpoint->loadMissing(['subscriptions:id,endpoint_id,event_type', 'latestDelivery', 'creator:id,email']);

        return response()->json([
            'endpoint' => $this->serializeEndpoint($endpoint, $user, false),
            'signing_secret_plaintext' => $secret,
        ], 201);
    }

    public function show(Request $request, string $id): JsonResponse
    {
        $user = $request->user();
        $endpoint = IntegrationWebhookEndpoint::query()
            ->with(['subscriptions:id,endpoint_id,event_type', 'latestDelivery', 'creator:id,email'])
            ->find($id);

        if (! $endpoint) {
            return response()->json(['message' => 'not_found'], 404);
        }

        return response()->json([
            'endpoint' => $this->serializeEndpoint($endpoint, $user, false),
        ]);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $user = $request->user();
        $endpoint = IntegrationWebhookEndpoint::query()->with('subscriptions')->find($id);

        if (! $endpoint) {
            return response()->json(['message' => 'not_found'], 404);
        }

        if (! $this->canManage($user?->role ?? '', $user?->id ?? '', $endpoint)) {
            return response()->json(['message' => 'forbidden'], 403);
        }

        $validator = Validator::make($request->all(), [
            'name' => ['sometimes', 'required', 'string', 'max:190'],
            'url' => ['sometimes', 'required', 'url', 'max:2048'],
            'status' => ['sometimes', Rule::in([
                IntegrationWebhookEndpoint::STATUS_ACTIVE,
                IntegrationWebhookEndpoint::STATUS_PAUSED,
                IntegrationWebhookEndpoint::STATUS_FAILING,
            ])],
            'retry_policy' => ['sometimes', Rule::in([
                IntegrationWebhookEndpoint::RETRY_EXPONENTIAL,
                IntegrationWebhookEndpoint::RETRY_LINEAR,
                IntegrationWebhookEndpoint::RETRY_NONE,
            ])],
            'max_retries' => ['sometimes', 'integer', 'min:0', 'max:10'],
            'timeout_ms' => ['sometimes', 'integer', 'min:500', 'max:30000'],
            'events' => ['sometimes', 'required', 'array', 'min:1'], 
            'events.*' => ['required_with:events', 'string', Rule::in(WebhookEventCatalog::all())],
        ]);

        if ($validator->fails()) {
            return response()->json(['message' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $data = $validator->validated();

        $endpoint->fill(array_intersect_key($data, array_flip([
            'name',
            'url',
            'status',
            'retry_policy',
            'max_retries',
            'timeout_ms',
        ])));
        $endpoint->updated_by = $user?->id;
        $endpoint->save();

        if (array_key_exists('events', $data)) {
            $this->syncSubscriptions($endpoint, $data['events']);
        }

        $endpoint->loadMissing(['subscriptions:id,endpoint_id,event_type', 'latestDelivery', 'creator:id,email']);

        return response()->json([
            'endpoint' => $this->serializeEndpoint($endpoint, $user, false),
        ]);
    }

    public function destroy(Request $request, string $id): JsonResponse
    {
        $user = $request->user();
        $endpoint = IntegrationWebhookEndpoint::find($id);
        if (! $endpoint) {
            return response()->json(['message' => 'not_found'], 404);
        }

        if (! $this->canManage($user?->role ?? '', $user?->id ?? '', $endpoint)) {
            return response()->json(['message' => 'forbidden'], 403);
        }

        $endpoint->delete();

        return response()->json(['status' => 'ok']);
    }

    public function pause(Request $request, string $id): JsonResponse
    {
        return $this->changeStatus($request, $id, IntegrationWebhookEndpoint::STATUS_PAUSED);
    }

    public function resume(Request $request, string $id): JsonResponse
    {
        return $this->changeStatus($request, $id, IntegrationWebhookEndpoint::STATUS_ACTIVE);
    }

    public function revealSecret(Request $request, string $id): JsonResponse
    {
        $user = $request->user();
        $endpoint = IntegrationWebhookEndpoint::find($id);
        if (! $endpoint) {
            return response()->json(['message' => 'not_found'], 404);
        }

        if (! $this->canManage($user?->role ?? '', $user?->id ?? '', $endpoint)) {
            return response()->json(['message' => 'forbidden'], 403);
        }

        return response()->json([
            'signing_algo' => $endpoint->signing_algo,
            'signing_secret_plaintext' => (string) $endpoint->signing_secret_encrypted,
        ]);
    }

    public function rotateSecret(Request $request, string $id): JsonResponse
    {
        $user = $request->user();
        $endpoint = IntegrationWebhookEndpoint::find($id);
        if (! $endpoint) {
            return response()->json(['message' => 'not_found'], 404);
        }

        if (! $this->canManage($user?->role ?? '', $user?->id ?? '', $endpoint)) {
            return response()->json(['message' => 'forbidden'], 403);
        }

        $secret = $this->generateSecret();
        $endpoint->update([
            'signing_secret_encrypted' => $secret,
            'updated_by' => $user?->id,
        ]);

        return response()->json([
            'status' => 'ok',
            'signing_secret_plaintext' => $secret,
        ]);
    }

    public function test(Request $request, string $id): JsonResponse
    {
        $user = $request->user();
        $endpoint = IntegrationWebhookEndpoint::query()->with('subscriptions')->find($id);
        if (! $endpoint) {
            return response()->json(['message' => 'not_found'], 404);
        }

        if (! $this->canManage($user?->role ?? '', $user?->id ?? '', $endpoint)) {
            return response()->json(['message' => 'forbidden'], 403);
        }

        $validator = Validator::make($request->all(), [
            'event_type' => ['nullable', 'string', Rule::in(WebhookEventCatalog::all())],
            'data' => ['nullable', 'array'],
        ]);

        if ($validator->fails()) {
            return response()->json(['message' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $data = $validator->validated();
        $eventType = (string) ($data['event_type'] ?? 'command.completed');

        $delivery = $this->publisher->enqueueForEndpoint($endpoint, $eventType, [
            'test' => true,
            'initiated_by' => $user?->email,
            'input' => $data['data'] ?? [],
        ]);

        return response()->json([
            'status' => 'queued',
            'delivery_id' => $delivery->id,
        ]);
    }

    private function changeStatus(Request $request, string $id, string $nextStatus): JsonResponse
    {
        $user = $request->user();
        $endpoint = IntegrationWebhookEndpoint::find($id);
        if (! $endpoint) {
            return response()->json(['message' => 'not_found'], 404);
        }

        if (! $this->canManage($user?->role ?? '', $user?->id ?? '', $endpoint)) {
            return response()->json(['message' => 'forbidden'], 403);
        }

        $endpoint->update([
            'status' => $nextStatus,
            'updated_by' => $user?->id,
        ]);

        return response()->json(['status' => 'ok']);
    }

    /**
     * @param  array<int,string>  $events
     */
    private function syncSubscriptions(IntegrationWebhookEndpoint $endpoint, array $events): void
    {
        $normalized = array_values(array_unique(array_map(static fn ($event) => trim((string) $event), $events)));
        $endpoint->subscriptions()->delete();
        foreach ($normalized as $eventType) {
            $endpoint->subscriptions()->create(['event_type' => $eventType]);
        }
    }

    private function canManage(string $role, string $userId, IntegrationWebhookEndpoint $endpoint): bool
    {
        if ($role === 'admin') {
            return true;
        }

        return $role === 'operator' && $userId !== '' && (string) $endpoint->created_by === $userId;
    }

    private function generateSecret(): string
    {
        return 'whsec_'.Str::lower(Str::random(48));
    }

    private function serializeEndpoint(IntegrationWebhookEndpoint $endpoint, mixed $user, bool $includePlainSecret): array
    {
        $events = $endpoint->subscriptions->pluck('event_type')->values()->all();
        $role = is_object($user) && isset($user->role) ? (string) $user->role : '';
        $userId = is_object($user) && isset($user->id) ? (string) $user->id : '';

        return [
            'id' => $endpoint->id,
            'name' => $endpoint->name,
            'url' => $endpoint->url,
            'status' => $endpoint->status,
            'events' => $events,
            'signing_algo' => $endpoint->signing_algo,
            'secret_masked' => $endpoint->secretMasked(),
            'retry_policy' => $endpoint->retry_policy,
            'max_retries' => $endpoint->max_retries,
            'timeout_ms' => $endpoint->timeout_ms,
            'total_deliveries' => (int) ($endpoint->success_count ?? 0) + (int) ($endpoint->dead_letter_count ?? 0) + (int) ($endpoint->retrying_count ?? 0),
            'success_count' => (int) ($endpoint->success_count ?? 0),
            'failure_count' => (int) ($endpoint->dead_letter_count ?? 0),
            'retrying_count' => (int) ($endpoint->retrying_count ?? 0),
            'last_delivery' => $endpoint->latestDelivery?->created_at?->toIso8601String(),
            'last_status' => $endpoint->latestDelivery?->http_status,
            'last_latency_ms' => $endpoint->latestDelivery?->latency_ms,
            'created_at' => $endpoint->created_at?->toIso8601String(),
            'updated_at' => $endpoint->updated_at?->toIso8601String(),
            'can_manage' => $this->canManage($role, $userId, $endpoint),
            'owner_user_id' => $endpoint->created_by,
            'owner_email' => $endpoint->creator?->email,
            'signing_secret_plaintext' => $includePlainSecret ? (string) $endpoint->signing_secret_encrypted : null,
        ];
    }
}
