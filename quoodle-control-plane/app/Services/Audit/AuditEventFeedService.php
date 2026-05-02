<?php

namespace App\Services\Audit;

use App\Models\Alert;
use App\Models\AuditTrail;
use App\Models\Command;
use App\Models\Device;
use App\Models\User;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;
use Illuminate\Support\Collection;

class AuditEventFeedService
{
    private const EVENT_TYPES = [
        'user_action',
        'command_execution',
        'policy_change',
        'system_event',
    ];

    private const OUTCOMES = [
        'success',
        'failure',
        'pending',
    ];

    /**
     * @return array{
     *   events: array<int, array<string, mixed>>,
     *   summary: array<string, int>,
     *   meta: array<string, int>,
     * }
     */
    public function list(Request $request, array $overrides = []): array
    {
        /** @var User|null $user */
        $user = $request->user();
        if (! $user) {
            return [
                'events' => [],
                'summary' => [
                    'total_events' => 0,
                    'success_count' => 0,
                    'failure_count' => 0,
                    'active_actors' => 0,
                ],
                'meta' => [
                    'current_page' => 1,
                    'last_page' => 1,
                    'per_page' => 0,
                    'total' => 0,
                ],
            ];
        }

        $filters = $this->normalizedFilters($request, $overrides);
        $visibleDeviceIds = $this->visibleDeviceIds($user);

        $events = collect()
            ->concat($this->commandEvents($user, $filters, $visibleDeviceIds))
            ->concat($this->alertEvents($user, $filters, $visibleDeviceIds))
            ->concat($this->auditTrailEvents($user, $filters, $visibleDeviceIds))
            ->values();

        $filtered = $events
            ->filter(fn (array $event): bool => $this->eventMatchesFilters($event, $filters))
            ->sortByDesc(fn (array $event): int => $this->parseIsoMillis($event['timestamp'] ?? null))
            ->values();

        $summary = [
            'total_events' => $filtered->count(),
            'success_count' => $filtered->where('outcome', 'success')->count(),
            'failure_count' => $filtered->where('outcome', 'failure')->count(),
            'active_actors' => $filtered
                ->pluck('actor')
                ->filter(fn (mixed $actor): bool => is_string($actor) && trim($actor) !== '')
                ->unique()
                ->count(),
        ];

        $paginate = ! ((bool) ($filters['for_export'] ?? false));
        if (! $paginate) {
            $limit = (int) ($filters['export_limit'] ?? 5000);
            $limited = $filtered->take(max(1, $limit))->values();

            return [
                'events' => $limited->all(),
                'summary' => $summary,
                'meta' => [
                    'current_page' => 1,
                    'last_page' => 1,
                    'per_page' => $limited->count(),
                    'total' => $limited->count(),
                ],
            ];
        }

        $perPage = max(1, (int) ($filters['per_page'] ?? 50));
        $page = max(1, (int) ($filters['page'] ?? 1));
        $total = $filtered->count();
        $lastPage = max(1, (int) ceil($total / $perPage));
        $currentPage = min($page, $lastPage);
        $offset = ($currentPage - 1) * $perPage;
        $paged = $filtered->slice($offset, $perPage)->values();

        return [
            'events' => $paged->all(),
            'summary' => $summary,
            'meta' => [
                'current_page' => $currentPage,
                'last_page' => $lastPage,
                'per_page' => $perPage,
                'total' => $total,
            ],
        ];
    }

    /**
     * @return Collection<int, string>
     */
    private function visibleDeviceIds(User $user): Collection
    {
        return Device::query()
            ->when(
                $user->role !== User::ROLE_ADMIN,
                fn (Builder $query): Builder => $query->where('user_id', $user->id)
            )
            ->pluck('device_id');
    }

    /**
     * @param  array<string, mixed>  $filters
     * @param  Collection<int, string>  $visibleDeviceIds
     * @return Collection<int, array<string, mixed>>
     */
    private function commandEvents(User $user, array $filters, Collection $visibleDeviceIds): Collection
    {
        $type = (string) ($filters['type'] ?? 'all');
        if ($type !== 'all' && $type !== 'command_execution') {
            return collect();
        }

        $query = Command::query()
            ->with(['user:id,email,role', 'device:device_id,user_id,device_name'])
            ->orderByDesc('queued_at')
            ->orderByDesc('id')
            ->limit((int) $filters['source_limit']);

        if ($user->role !== User::ROLE_ADMIN) {
            $query->whereHas('device', fn (Builder $deviceQuery): Builder => $deviceQuery->where('user_id', $user->id));
        }

        $deviceId = (string) ($filters['device_id'] ?? '');
        if ($deviceId !== '') {
            $query->where('device_id', $deviceId);
        }

        $commands = $query->get();

        return $commands->map(function (Command $command): array {
            $timestamp = optional($command->completed_at ?? $command->queued_at ?? $command->created_at)?->toIso8601String();
            $state = strtolower((string) ($command->state ?? 'queued'));
            $actor = $command->user?->email ?? 'system';
            $actorRole = $command->user?->role ? ucfirst($command->user->role) : $this->inferActorRole($actor);
            $outcome = match ($state) {
                'completed' => 'success',
                'failed', 'expired', 'rejected' => 'failure',
                default => 'pending',
            };
            $detail = trim((string) $command->method).' ('.$command->id.')';
            if (is_string($command->error_message) && trim($command->error_message) !== '') {
                $detail .= ' - '.trim($command->error_message);
            }

            return [
                'id' => 'cmd-'.$command->id,
                'timestamp' => $timestamp,
                'actor' => $actor,
                'actor_role' => $actorRole,
                'event_type' => 'command_execution',
                'action' => 'COMMAND_'.strtoupper($state),
                'target' => (string) $command->device_id,
                'detail' => $detail,
                'outcome' => $outcome,
                'source' => 'commands',
                'device_id' => (string) $command->device_id,
                'severity' => null,
                'command_state' => $state,
                'command_method' => (string) $command->method,
            ];
        });
    }

    /**
     * @param  array<string, mixed>  $filters
     * @param  Collection<int, string>  $visibleDeviceIds
     * @return Collection<int, array<string, mixed>>
     */
    private function alertEvents(User $user, array $filters, Collection $visibleDeviceIds): Collection
    {
        if ($user->role === User::ROLE_VIEWER) {
            return collect();
        }

        $type = (string) ($filters['type'] ?? 'all');
        if ($type !== 'all' && $type !== 'system_event' && $type !== 'user_action') {
            return collect();
        }

        $query = Alert::query()
            ->orderByDesc('timestamp')
            ->orderByDesc('id')
            ->limit((int) $filters['source_limit']);

        if ($user->role !== User::ROLE_ADMIN) {
            if ($visibleDeviceIds->isEmpty()) {
                return collect();
            }
            $query->whereIn('device_id', $visibleDeviceIds);
        }

        $deviceId = (string) ($filters['device_id'] ?? '');
        if ($deviceId !== '') {
            $query->where('device_id', $deviceId);
        }

        return $query->get()->map(function (Alert $alert): array {
            $severity = strtolower(trim((string) $alert->severity));
            $acknowledged = (bool) $alert->acknowledged;

            return [
                'id' => 'alt-'.$alert->id,
                'timestamp' => optional($alert->timestamp)?->toIso8601String(),
                'actor' => 'system',
                'actor_role' => 'System',
                'event_type' => 'system_event',
                'action' => $acknowledged ? 'ALERT_ACKNOWLEDGED' : 'ALERT_RAISED',
                'target' => (string) ($alert->device_id ?: $alert->alert_id),
                'detail' => (string) $alert->message,
                'outcome' => $acknowledged ? 'success' : (in_array($severity, ['critical', 'high'], true) ? 'failure' : 'pending'),
                'source' => 'alerts',
                'device_id' => $alert->device_id,
                'severity' => $severity,
                'acknowledged' => $acknowledged,
                'alert_id' => (string) $alert->alert_id,
            ];
        });
    }

    /**
     * @param  array<string, mixed>  $filters
     * @param  Collection<int, string>  $visibleDeviceIds
     * @return Collection<int, array<string, mixed>>
     */
    private function auditTrailEvents(User $user, array $filters, Collection $visibleDeviceIds): Collection
    {
        $query = AuditTrail::query()
            ->orderByDesc('timestamp')
            ->orderByDesc('id')
            ->limit((int) $filters['source_limit']);

        if ($user->role !== User::ROLE_ADMIN) {
            $query->where(function (Builder $scope) use ($visibleDeviceIds, $user): void {
                if (! $visibleDeviceIds->isEmpty()) {
                    $scope->whereIn('device_id', $visibleDeviceIds);
                }
                $scope->orWhere(function (Builder $nullScope) use ($user): void {
                    $nullScope->whereNull('device_id')->where('actor_id', (string) $user->id);
                });
            });
        }

        $deviceId = (string) ($filters['device_id'] ?? '');
        if ($deviceId !== '') {
            $query->where('device_id', $deviceId);
        }

        return $query->get()->map(function (AuditTrail $entry): array {
            $rawEvent = strtolower(trim((string) $entry->event_type));
            $eventType = $this->canonicalEventType($rawEvent);
            $action = strtoupper(str_replace(['-', ' '], '_', $rawEvent !== '' ? $rawEvent : 'event'));
            $actor = trim((string) $entry->actor) !== '' ? (string) $entry->actor : 'system';
            $outcome = $this->inferAuditTrailOutcome($rawEvent);

            return [
                'id' => 'atr-'.$entry->id,
                'timestamp' => optional($entry->timestamp)?->toIso8601String(),
                'actor' => $actor,
                'actor_role' => $this->inferActorRole($actor),
                'event_type' => $eventType,
                'action' => $action,
                'target' => (string) ($entry->device_id ?: $entry->audit_id),
                'detail' => $rawEvent !== '' ? $rawEvent.' event' : 'audit event',
                'outcome' => $outcome,
                'source' => 'audit_trail',
                'device_id' => $entry->device_id,
                'severity' => null,
            ];
        });
    }

    /**
     * @param  array<string, mixed>  $event
     * @param  array<string, mixed>  $filters
     */
    private function eventMatchesFilters(array $event, array $filters): bool
    {
        $timestamp = $event['timestamp'] ?? null;
        $tsMs = $this->parseIsoMillis(is_string($timestamp) ? $timestamp : null);

        $from = $filters['from'];
        if ($from instanceof CarbonImmutable && $tsMs > 0 && $tsMs < $from->getTimestampMs()) {
            return false;
        }

        $to = $filters['to'];
        if ($to instanceof CarbonImmutable && $tsMs > 0 && $tsMs > $to->getTimestampMs()) {
            return false;
        }

        $eventType = (string) ($event['event_type'] ?? '');
        $typeFilter = (string) ($filters['type'] ?? 'all');
        if ($typeFilter !== 'all' && $eventType !== $typeFilter) {
            return false;
        }

        $outcomeFilter = (string) ($filters['outcome'] ?? 'all');
        if ($outcomeFilter !== 'all' && (string) ($event['outcome'] ?? '') !== $outcomeFilter) {
            return false;
        }

        $actorFilter = strtolower((string) ($filters['actor'] ?? ''));
        if ($actorFilter !== '') {
            $actorValue = strtolower((string) ($event['actor'] ?? ''));
            if (! str_contains($actorValue, $actorFilter)) {
                return false;
            }
        }

        $deviceFilter = (string) ($filters['device_id'] ?? '');
        if ($deviceFilter !== '' && (string) ($event['device_id'] ?? '') !== $deviceFilter) {
            return false;
        }

        if ((bool) ($filters['compliance_only'] ?? false) && ! $this->isComplianceRelevant($event)) {
            return false;
        }

        $q = strtolower((string) ($filters['q'] ?? ''));
        if ($q !== '') {
            $haystack = strtolower(implode(' ', [
                (string) ($event['actor'] ?? ''),
                (string) ($event['action'] ?? ''),
                (string) ($event['target'] ?? ''),
                (string) ($event['detail'] ?? ''),
                (string) ($event['event_type'] ?? ''),
                (string) ($event['source'] ?? ''),
            ]));

            if (! str_contains($haystack, $q)) {
                return false;
            }
        }

        return true;
    }

    /**
     * @param  array<string, mixed>  $event
     */
    private function isComplianceRelevant(array $event): bool
    {
        if ((string) ($event['event_type'] ?? '') === 'policy_change') {
            return true;
        }

        $haystack = strtolower(implode(' ', [
            (string) ($event['action'] ?? ''),
            (string) ($event['detail'] ?? ''),
            (string) ($event['target'] ?? ''),
        ]));

        foreach (['compliance', 'policy', 'attestation', 'kernel', 'quarantine', 'heartbeat', 'sync', 'certificate', 'drift'] as $needle) {
            if (str_contains($haystack, $needle)) {
                return true;
            }
        }

        return false;
    }

    /**
     * @param  array<string, mixed>  $overrides
     * @return array{
     *   page: int,
     *   per_page: int,
     *   q: string,
     *   type: string,
     *   outcome: string,
     *   actor: string,
     *   device_id: string,
     *   from: ?CarbonImmutable,
     *   to: ?CarbonImmutable,
     *   source_limit: int,
     *   for_export: bool,
     *   export_limit: int,
     *   compliance_only: bool
     * }
     */
    private function normalizedFilters(Request $request, array $overrides): array
    {
        $rawType = strtolower(trim((string) ($overrides['type'] ?? $request->query('type', 'all'))));
        $type = in_array($rawType, array_merge(['all'], self::EVENT_TYPES), true) ? $rawType : 'all';

        $rawOutcome = strtolower(trim((string) ($overrides['outcome'] ?? $request->query('outcome', 'all'))));
        $outcome = in_array($rawOutcome, array_merge(['all'], self::OUTCOMES), true) ? $rawOutcome : 'all';

        $fromRaw = trim((string) ($overrides['from'] ?? $request->query('from', '')));
        $toRaw = trim((string) ($overrides['to'] ?? $request->query('to', '')));
        $from = $this->parseCarbon($fromRaw);
        $to = $this->parseCarbon($toRaw);
        if ($to instanceof CarbonImmutable) {
            $to = $to->addDay()->subSecond();
        }

        return [
            'page' => max(1, (int) ($overrides['page'] ?? $request->query('page', 1))),
            'per_page' => min(max((int) ($overrides['per_page'] ?? $request->query('per_page', 50)), 1), 200),
            'q' => trim((string) ($overrides['q'] ?? $request->query('q', ''))),
            'type' => $type,
            'outcome' => $outcome,
            'actor' => trim((string) ($overrides['actor'] ?? $request->query('actor', ''))),
            'device_id' => trim((string) ($overrides['device_id'] ?? $request->query('device_id', ''))),
            'from' => $from,
            'to' => $to,
            'source_limit' => min(max((int) ($overrides['source_limit'] ?? 2000), 200), 5000),
            'for_export' => (bool) ($overrides['for_export'] ?? false),
            'export_limit' => min(max((int) ($overrides['export_limit'] ?? 5000), 1), 10000),
            'compliance_only' => (bool) ($overrides['compliance_only'] ?? false),
        ];
    }

    private function parseCarbon(string $value): ?CarbonImmutable
    {
        if ($value === '') {
            return null;
        }

        try {
            return CarbonImmutable::parse($value)->utc();
        } catch (\Throwable) {
            return null;
        }
    }

    private function parseIsoMillis(?string $value): int
    {
        if (! is_string($value) || trim($value) === '') {
            return 0;
        }

        $parsed = strtotime($value);
        if ($parsed === false) {
            return 0;
        }

        return $parsed * 1000;
    }

    private function canonicalEventType(string $raw): string
    {
        if (in_array($raw, self::EVENT_TYPES, true)) {
            return $raw;
        }
        if (str_contains($raw, 'policy')) {
            return 'policy_change';
        }
        if (str_contains($raw, 'command')) {
            return 'command_execution';
        }
        if (str_contains($raw, 'login') || str_contains($raw, 'user') || str_contains($raw, 'ack')) {
            return 'user_action';
        }

        return 'system_event';
    }

    private function inferAuditTrailOutcome(string $rawEvent): string
    {
        $event = strtolower($rawEvent);
        foreach (['fail', 'error', 'reject', 'deny', 'blocked'] as $failureNeedle) {
            if (str_contains($event, $failureNeedle)) {
                return 'failure';
            }
        }
        foreach (['success', 'ok', 'complete', 'updated', 'synced', 'ack', 'login', 'allow'] as $successNeedle) {
            if (str_contains($event, $successNeedle)) {
                return 'success';
            }
        }

        return 'pending';
    }

    private function inferActorRole(string $actor): string
    {
        $value = strtolower(trim($actor));
        if ($value === 'system' || $value === '') {
            return 'System';
        }
        if (str_contains($value, 'admin')) {
            return 'Admin';
        }
        if (str_contains($value, 'viewer')) {
            return 'Viewer';
        }

        return 'Operator';
    }
}
