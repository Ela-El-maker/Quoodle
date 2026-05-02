<?php

namespace App\Http\Controllers\Notifications;

use App\Http\Controllers\Controller;
use App\Models\NotificationReceipt;
use App\Models\User;
use App\Services\Audit\AuditEventFeedService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\Rule;

final class NotificationsController extends Controller
{
    public function __construct(private readonly AuditEventFeedService $auditFeed)
    {
    }

    public function index(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'limit' => ['nullable', 'integer', 'min:1', 'max:200'],
            'q' => ['nullable', 'string', 'max:200'],
            'device_id' => ['nullable', 'string', 'max:190'],
            'type' => ['nullable', Rule::in(['all', 'alert', 'command', 'device_state', 'system'])],
            'read' => ['nullable', Rule::in(['all', 'read', 'unread'])],
            'include_dismissed' => ['nullable', 'boolean'],
            'from' => ['nullable', 'string'],
            'to' => ['nullable', 'string'],
        ]);

        if ($validator->fails()) {
            return response()->json(['message' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        /** @var User|null $user */
        $user = $request->user();
        if (! $user) {
            return response()->json(['message' => 'unauthenticated'], 401);
        }

        $filters = $validator->validated();
        $limit = (int) ($filters['limit'] ?? 60);
        $readFilter = (string) ($filters['read'] ?? 'all');
        $includeDismissed = (bool) ($filters['include_dismissed'] ?? false);

        $notifications = $this->buildNotifications(
            $request,
            $user,
            $limit,
            $includeDismissed,
            $filters,
        );

        if ($readFilter === 'read') {
            $notifications = $notifications->where('read', true)->values();
        } elseif ($readFilter === 'unread') {
            $notifications = $notifications->where('read', false)->values();
        }

        $items = $notifications->take($limit)->values();

        return response()->json([
            'notifications' => $items,
            'summary' => [
                'total' => $items->count(),
                'unread' => $items->where('read', false)->count(),
                'alerts' => $items->where('type', 'alert')->count(),
                'commands' => $items->where('type', 'command')->count(),
                'device_state' => $items->where('type', 'device_state')->count(),
                'system' => $items->where('type', 'system')->count(),
            ],
        ]);
    }

    public function markRead(Request $request, string $notificationId): JsonResponse
    {
        /** @var User|null $user */
        $user = $request->user();
        if (! $user) {
            return response()->json(['message' => 'unauthenticated'], 401);
        }

        NotificationReceipt::query()->updateOrCreate(
            [
                'user_id' => (string) $user->id,
                'event_id' => $notificationId,
            ],
            [
                'read_at' => now(),
            ],
        );

        return response()->json([
            'status' => 'ok',
            'notification_id' => $notificationId,
            'read_at' => now()->toIso8601String(),
        ]);
    }

    public function markAllRead(Request $request): JsonResponse
    {
        /** @var User|null $user */
        $user = $request->user();
        if (! $user) {
            return response()->json(['message' => 'unauthenticated'], 401);
        }

        $validator = Validator::make($request->all(), [
            'q' => ['nullable', 'string', 'max:200'],
            'device_id' => ['nullable', 'string', 'max:190'],
            'type' => ['nullable', Rule::in(['all', 'alert', 'command', 'device_state', 'system'])],
            'include_dismissed' => ['nullable', 'boolean'],
            'from' => ['nullable', 'string'],
            'to' => ['nullable', 'string'],
        ]);

        if ($validator->fails()) {
            return response()->json(['message' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $filters = $validator->validated();
        $notifications = $this->buildNotifications(
            $request,
            $user,
            500,
            (bool) ($filters['include_dismissed'] ?? false),
            $filters,
        );

        $now = now();
        $rows = $notifications
            ->pluck('id')
            ->filter(fn (mixed $id): bool => is_string($id) && trim($id) !== '')
            ->unique()
            ->map(fn (string $id): array => [
                'id' => (string) str()->ulid(),
                'user_id' => (string) $user->id,
                'event_id' => $id,
                'read_at' => $now,
                'created_at' => $now,
                'updated_at' => $now,
            ])
            ->values()
            ->all();

        if ($rows !== []) {
            NotificationReceipt::query()->upsert(
                $rows,
                ['user_id', 'event_id'],
                ['read_at', 'updated_at'],
            );
        }

        return response()->json([
            'status' => 'ok',
            'marked' => count($rows),
            'read_at' => $now->toIso8601String(),
        ]);
    }

    public function dismiss(Request $request, string $notificationId): JsonResponse
    {
        /** @var User|null $user */
        $user = $request->user();
        if (! $user) {
            return response()->json(['message' => 'unauthenticated'], 401);
        }

        NotificationReceipt::query()->updateOrCreate(
            [
                'user_id' => (string) $user->id,
                'event_id' => $notificationId,
            ],
            [
                'read_at' => now(),
                'dismissed_at' => now(),
            ],
        );

        return response()->json([
            'status' => 'ok',
            'notification_id' => $notificationId,
            'dismissed_at' => now()->toIso8601String(),
        ]);
    }

    /**
     * @param  array<string, mixed>  $filters
     * @return Collection<int, array<string, mixed>>
     */
    private function buildNotifications(
        Request $request,
        User $user,
        int $limit,
        bool $includeDismissed,
        array $filters,
    ): Collection {
        $auditPayload = $this->auditFeed->list($request, [
            'page' => 1,
            'per_page' => min(max($limit * 4, 200), 800),
            'source_limit' => 3000,
            'q' => (string) ($filters['q'] ?? ''),
            'device_id' => (string) ($filters['device_id'] ?? ''),
            'from' => (string) ($filters['from'] ?? ''),
            'to' => (string) ($filters['to'] ?? ''),
        ]);

        $notifications = collect($auditPayload['events'] ?? [])
            ->filter(fn (mixed $event): bool => is_array($event))
            ->map(function (array $event): array {
                $type = $this->toNotificationType($event);
                $severity = $this->toSeverity($event, $type);
                $title = $this->toTitle($event, $type);

                return [
                    'id' => (string) ($event['id'] ?? ''),
                    'type' => $type,
                    'severity' => $severity,
                    'title' => $title,
                    'message' => (string) ($event['detail'] ?? $title),
                    'device_id' => (string) ($event['device_id'] ?? ''),
                    'actor' => (string) ($event['actor'] ?? 'system'),
                    'timestamp' => (string) ($event['timestamp'] ?? ''),
                    'source' => (string) ($event['source'] ?? ''),
                    'outcome' => (string) ($event['outcome'] ?? 'pending'),
                ];
            })
            ->filter(fn (array $item): bool => $item['id'] !== '');

        $requestedType = strtolower(trim((string) ($filters['type'] ?? 'all')));
        if ($requestedType !== '' && $requestedType !== 'all') {
            $notifications = $notifications->where('type', $requestedType)->values();
        }

        $receipts = NotificationReceipt::query()
            ->where('user_id', (string) $user->id)
            ->whereIn('event_id', $notifications->pluck('id')->all())
            ->get()
            ->keyBy('event_id');

        return $notifications
            ->map(function (array $item) use ($receipts): array {
                /** @var NotificationReceipt|null $receipt */
                $receipt = $receipts->get($item['id']);

                $item['read'] = (bool) ($receipt?->read_at);
                $item['dismissed'] = (bool) ($receipt?->dismissed_at);
                $item['read_at'] = $receipt?->read_at?->toIso8601String();
                $item['dismissed_at'] = $receipt?->dismissed_at?->toIso8601String();

                return $item;
            })
            ->filter(fn (array $item): bool => $includeDismissed || ! $item['dismissed'])
            ->values();
    }

    /**
     * @param  array<string, mixed>  $event
     */
    private function toNotificationType(array $event): string
    {
        $source = strtolower((string) ($event['source'] ?? ''));
        if ($source === 'alerts') {
            return 'alert';
        }
        if ($source === 'commands') {
            return 'command';
        }

        $action = strtolower((string) ($event['action'] ?? ''));
        if (str_contains($action, 'offline') || str_contains($action, 'online') || str_contains($action, 'heartbeat') || str_contains($action, 'presence')) {
            return 'device_state';
        }

        return 'system';
    }

    /**
     * @param  array<string, mixed>  $event
     */
    private function toSeverity(array $event, string $type): string
    {
        $raw = strtolower(trim((string) ($event['severity'] ?? '')));
        if (in_array($raw, ['critical', 'high', 'warning', 'medium', 'low', 'info'], true)) {
            return $raw;
        }

        $outcome = strtolower((string) ($event['outcome'] ?? 'pending'));
        if ($type === 'device_state') {
            $action = strtolower((string) ($event['action'] ?? ''));
            if (str_contains($action, 'offline')) {
                return 'high';
            }
        }

        return match ($outcome) {
            'failure' => 'high',
            'success' => 'info',
            default => 'medium',
        };
    }

    /**
     * @param  array<string, mixed>  $event
     */
    private function toTitle(array $event, string $type): string
    {
        $action = strtolower((string) ($event['action'] ?? 'event'));
        $method = strtolower((string) ($event['command_method'] ?? ''));
        $detail = trim((string) ($event['detail'] ?? ''));
        $humanAction = str_replace('_', ' ', $action);
        $humanAction = ucwords($humanAction);

        if ($type === 'command') {
            if ($method !== '') {
                return 'Command '.strtoupper((string) ($event['command_state'] ?? 'update')).': '.$method;
            }

            return $humanAction;
        }

        if ($type === 'alert') {
            return $this->truncate($detail !== '' ? $detail : 'Alert', 96);
        }

        if ($type === 'device_state') {
            return $humanAction;
        }

        return $this->truncate($detail !== '' ? $detail : $humanAction, 96);
    }

    private function truncate(string $value, int $max): string
    {
        $trimmed = trim($value);
        if ($trimmed === '') {
            return '';
        }
        if (strlen($trimmed) <= $max) {
            return $trimmed;
        }

        return rtrim(substr($trimmed, 0, max(1, $max - 3))).'...';
    }
}
