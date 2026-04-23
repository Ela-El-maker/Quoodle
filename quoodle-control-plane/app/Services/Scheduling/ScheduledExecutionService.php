<?php

namespace App\Services\Scheduling;

use App\Models\Command;
use App\Models\Device;
use App\Models\ScheduledJob;
use App\Models\ScheduledJobRun;
use App\Models\ScheduledJobRunItem;
use App\Services\CommandRegistry\Registry;
use App\Services\Commands\CommandService;
use Carbon\CarbonImmutable;
use Cron\CronExpression;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

class ScheduledExecutionService
{
    public function __construct(
        private readonly Registry $registry,
        private readonly CommandService $commandService,
    ) {
    }

    /**
     * @return array{ok: bool, reason: string|null, definition: CommandDefinition|null}
     */
    public function assessSchedulableMethod(string $method, string $actorRole): array
    {
        $definition = $this->registry->get($method);
        if (! $definition) {
            return ['ok' => false, 'reason' => 'unknown_command', 'definition' => null];
        }

        if (! $definition->isRoleAllowed($actorRole)) {
            return ['ok' => false, 'reason' => 'role_not_allowed', 'definition' => $definition];
        }

        if ($definition->requires2fa || $definition->riskLevel === 'high') {
            return ['ok' => false, 'reason' => 'method_not_schedulable', 'definition' => $definition];
        }

        return ['ok' => true, 'reason' => null, 'definition' => $definition];
    }

    public function isValidCron(string $expression): bool
    {
        return CronExpression::isValidExpression($expression);
    }

    public function isValidTimezone(string $timezone): bool
    {
        return in_array($timezone, timezone_identifiers_list(), true);
    }

    public function computeNextRunAt(string $cronExpression, string $timezone, ?CarbonImmutable $fromUtc = null): CarbonImmutable
    {
        $fromUtc = $fromUtc ?? CarbonImmutable::now('UTC');
        $fromTz = $fromUtc->setTimezone($timezone);
        $next = CronExpression::factory($cronExpression)->getNextRunDate($fromTz->toDateTimeImmutable(), 0, false, $timezone);

        return CarbonImmutable::instance($next)->setTimezone('UTC');
    }

    /**
     * @param  array<int, string>  $targetIds
     * @return array<int, string>
     */
    public function resolveTargetDeviceIds(string $targetType, array $targetIds, string $actorRole, ?string $actorUserId): array
    {
        $query = $this->visibleDevicesQuery($actorRole, $actorUserId);

        if ($targetType === 'all') {
            return $query->pluck('device_id')->all();
        }

        if ($targetType === 'device') {
            $ids = array_values(array_unique(array_filter(array_map('trim', $targetIds), static fn (string $value): bool => $value !== '')));
            if ($ids === []) {
                return [];
            }

            return $query->whereIn('device_id', $ids)->pluck('device_id')->all();
        }

        if ($targetType === 'group') {
            $groupIds = array_values(array_unique(array_filter(array_map('trim', $targetIds), static fn (string $value): bool => $value !== '')));
            if ($groupIds === []) {
                return [];
            }

            if ($actorRole !== 'admin') {
                $groupIds = array_values(array_filter($groupIds, static fn (string $candidate): bool => $candidate === $actorUserId));
                if ($groupIds === []) {
                    return [];
                }
            }

            return $query->whereIn('user_id', $groupIds)->pluck('device_id')->all();
        }

        return [];
    }

    /**
     * @return array{processed: int, claimed: int, failed: int}
     */
    public function dispatchDueJobs(int $limit = 100): array
    {
        $limit = max(1, min($limit, 500));
        $nowUtc = CarbonImmutable::now('UTC');

        $this->reconcileRunStatuses($nowUtc, $limit * 5);

        $dueIds = ScheduledJob::query()
            ->where('enabled', true)
            ->whereNotNull('next_run_at')
            ->where('next_run_at', '<=', $nowUtc)
            ->orderBy('next_run_at')
            ->limit($limit)
            ->pluck('id');

        $processed = 0;
        $claimed = 0;
        $failed = 0;

        foreach ($dueIds as $jobId) {
            $processed++;
            $run = $this->claimDueRun($jobId, $nowUtc);
            if (! $run) {
                continue;
            }

            $claimed++;

            try {
                $this->dispatchRunItems($run->id);
            } catch (\Throwable $exception) {
                $failed++;
                report($exception);

                ScheduledJobRun::whereKey($run->id)->update([
                    'status' => 'failed',
                    'error_message' => 'dispatch_exception',
                    'finished_at' => CarbonImmutable::now('UTC'),
                ]);
            }
        }

        return [
            'processed' => $processed,
            'claimed' => $claimed,
            'failed' => $failed,
        ];
    }

    public function runNow(ScheduledJob $job): ScheduledJobRun
    {
        $nowUtc = CarbonImmutable::now('UTC');

        $run = DB::transaction(function () use ($job, $nowUtc): ScheduledJobRun {
            /** @var ScheduledJob|null $locked */
            $locked = ScheduledJob::query()->whereKey($job->id)->lockForUpdate()->first();
            if (! $locked) {
                throw new \RuntimeException('schedule_not_found');
            }

            $scheduledFor = $this->ensureUniqueScheduledFor($locked->id, $nowUtc);

            $run = ScheduledJobRun::create([
                'job_id' => $locked->id,
                'trigger' => 'manual',
                'scheduled_for' => $scheduledFor,
                'status' => 'running',
                'started_at' => $nowUtc,
            ]);

            $locked->last_run_at = $nowUtc;
            $locked->save();

            return $run;
        });

        $this->dispatchRunItems($run->id);

        return ScheduledJobRun::query()->with(['job', 'items'])->findOrFail($run->id);
    }

    public function reconcileRuns(int $limit = 500): void
    {
        $this->reconcileRunStatuses(CarbonImmutable::now('UTC'), $limit);
    }

    private function claimDueRun(string $jobId, CarbonImmutable $nowUtc): ?ScheduledJobRun
    {
        return DB::transaction(function () use ($jobId, $nowUtc): ?ScheduledJobRun {
            /** @var ScheduledJob|null $job */
            $job = ScheduledJob::query()->whereKey($jobId)->lockForUpdate()->first();
            if (! $job || ! $job->enabled || ! $job->next_run_at) {
                return null;
            }

            $scheduledFor = CarbonImmutable::instance($job->next_run_at)->setTimezone('UTC');
            if ($scheduledFor->greaterThan($nowUtc)) {
                return null;
            }

            $run = ScheduledJobRun::query()->firstOrCreate(
                [
                    'job_id' => $job->id,
                    'scheduled_for' => $scheduledFor,
                ],
                [
                    'trigger' => 'schedule',
                    'status' => 'running',
                    'started_at' => $nowUtc,
                ],
            );

            if (! $run->wasRecentlyCreated) {
                return null;
            }

            // Single catch-up policy: execute once now, then jump to first future window.
            $job->last_run_at = $nowUtc;
            $job->next_run_at = $this->computeNextRunAt($job->cron_expression, $job->timezone, $nowUtc);
            $job->save();

            return $run;
        });
    }

    private function dispatchRunItems(string $runId): void
    {
        $nowUtc = CarbonImmutable::now('UTC');

        /** @var ScheduledJobRun|null $run */
        $run = ScheduledJobRun::query()->with('job')->find($runId);
        if (! $run || ! $run->job) {
            return;
        }

        $job = $run->job;
        $deviceIds = $this->resolveTargetDeviceIds(
            $job->target_type,
            is_array($job->target_ids) ? $job->target_ids : [],
            $job->created_by_role,
            $job->created_by_user_id,
        );

        $uniqueDeviceIds = array_values(array_unique($deviceIds));

        if ($uniqueDeviceIds === []) {
            $run->update([
                'status' => 'failed',
                'error_message' => 'no_target_devices',
                'total_targets' => 0,
                'dispatched_count' => 0,
                'failed_count' => 0,
                'result_summary' => [
                    'accepted' => 0,
                    'failed' => 0,
                ],
                'finished_at' => $nowUtc,
            ]);

            return;
        }

        $assessed = $this->assessSchedulableMethod($job->method, $job->created_by_role);
        if (! $assessed['ok']) {
            $run->update([
                'status' => 'failed',
                'error_message' => $assessed['reason'] ?? 'method_not_schedulable',
                'total_targets' => count($uniqueDeviceIds),
                'dispatched_count' => 0,
                'failed_count' => count($uniqueDeviceIds),
                'result_summary' => [
                    'accepted' => 0,
                    'failed' => count($uniqueDeviceIds),
                    'reason' => $assessed['reason'] ?? 'method_not_schedulable',
                ],
                'finished_at' => $nowUtc,
            ]);

            return;
        }

        $accepted = 0;
        $failed = 0;

        foreach ($uniqueDeviceIds as $deviceId) {
            $item = ScheduledJobRunItem::query()->firstOrCreate(
                [
                    'run_id' => $run->id,
                    'device_id' => $deviceId,
                ],
                [
                    'status' => 'pending',
                    'started_at' => $nowUtc,
                ],
            );

            if (! $item->wasRecentlyCreated) {
                continue;
            }

            $clientMessageId = $this->deterministicClientMessageId($job->id, $run->scheduled_for?->toIso8601String() ?? $nowUtc->toIso8601String(), $deviceId);

            $payload = [
                'client_message_id' => $clientMessageId,
                'device_id' => $deviceId,
                'method' => $job->method,
                'params' => is_array($job->params) ? $job->params : [],
                'sensitive' => false,
                'user_id' => $job->created_by_user_id,
                'user_role' => $job->created_by_role,
                'origin_channel' => 'schedule',
            ];

            $result = $this->commandService->enqueue($payload);

            if (($result['status'] ?? '') === 'accepted' && isset($result['command']) && $result['command'] instanceof Command) {
                $accepted++;
                $item->update([
                    'status' => 'running',
                    'command_id' => $result['command']->id,
                    'result_summary' => [
                        'state' => $result['state'] ?? 'queued',
                    ],
                ]);
            } else {
                $failed++;
                $item->update([
                    'status' => 'failed',
                    'error_message' => (string) ($result['reason'] ?? 'dispatch_failed'),
                    'result_summary' => [
                        'status' => (string) ($result['status'] ?? 'rejected'),
                    ],
                    'finished_at' => CarbonImmutable::now('UTC'),
                ]);
            }
        }

        $run->update([
            'status' => $accepted > 0 ? 'running' : 'failed',
            'total_targets' => count($uniqueDeviceIds),
            'dispatched_count' => $accepted,
            'failed_count' => $failed,
            'result_summary' => [
                'accepted' => $accepted,
                'failed' => $failed,
            ],
            'error_message' => $accepted > 0 ? null : 'all_dispatches_failed',
            'finished_at' => $accepted > 0 ? null : CarbonImmutable::now('UTC'),
        ]);
    }

    private function reconcileRunStatuses(CarbonImmutable $nowUtc, int $limit): void
    {
        $limit = max(1, min($limit, 1000));

        $runs = ScheduledJobRun::query()
            ->whereIn('status', ['pending', 'running'])
            ->orderBy('started_at')
            ->limit($limit)
            ->get();

        foreach ($runs as $run) {
            $items = ScheduledJobRunItem::query()
                ->where('run_id', $run->id)
                ->with('command:id,state,execution_state,completed_at,error_message,reason')
                ->get();

            if ($items->isEmpty()) {
                continue;
            }

            $success = 0;
            $failed = 0;
            $running = 0;

            foreach ($items as $item) {
                $derived = $this->deriveItemState($item);
                if ($derived === 'success') {
                    $success++;
                } elseif ($derived === 'failed') {
                    $failed++;
                } else {
                    $running++;
                }

                $nextFinishedAt = in_array($derived, ['success', 'failed'], true)
                    ? ($item->command?->completed_at ?? $item->finished_at ?? $nowUtc)
                    : null;

                if ($item->status !== $derived || ($nextFinishedAt && $item->finished_at?->toIso8601String() !== $nextFinishedAt->toIso8601String())) {
                    $item->update([
                        'status' => $derived,
                        'error_message' => $derived === 'failed'
                            ? ($item->command?->error_message ?: $item->command?->reason ?: $item->error_message)
                            : null,
                        'finished_at' => $nextFinishedAt,
                    ]);
                }
            }

            $nextRunStatus = $running > 0 ? 'running' : ($failed > 0 ? 'failed' : 'success');
            $dispatchedCount = $success + $running;
            $totalTargets = $success + $failed + $running;

            $run->update([
                'status' => $nextRunStatus,
                'total_targets' => $totalTargets,
                'dispatched_count' => $dispatchedCount,
                'failed_count' => $failed,
                'result_summary' => [
                    'success' => $success,
                    'failed' => $failed,
                    'running' => $running,
                ],
                'finished_at' => $running > 0 ? null : ($run->finished_at ?? $nowUtc),
            ]);
        }
    }

    private function deriveItemState(ScheduledJobRunItem $item): string
    {
        if ($item->command) {
            $state = (string) ($item->command->execution_state ?: $item->command->state ?: 'queued');
            if ($state === 'completed') {
                return 'success';
            }

            if (in_array($state, ['failed', 'expired', 'rejected'], true)) {
                return 'failed';
            }

            return 'running';
        }

        return $item->status === 'failed' ? 'failed' : 'running';
    }

    private function ensureUniqueScheduledFor(string $jobId, CarbonImmutable $base): CarbonImmutable
    {
        $candidate = $base->startOfSecond();

        for ($attempt = 0; $attempt < 10; $attempt++) {
            $exists = ScheduledJobRun::query()
                ->where('job_id', $jobId)
                ->where('scheduled_for', $candidate)
                ->exists();

            if (! $exists) {
                return $candidate;
            }

            $candidate = $candidate->addSecond();
        }

        return $candidate;
    }

    private function deterministicClientMessageId(string $jobId, string $scheduledForIso, string $deviceId): string
    {
        $digest = hash('sha256', $jobId.'|'.$scheduledForIso.'|'.$deviceId);

        return 'sched-'.$digest;
    }

    private function visibleDevicesQuery(string $actorRole, ?string $actorUserId): Builder
    {
        $query = Device::query();
        if ($actorRole !== 'admin') {
            $query->where('user_id', $actorUserId);
        }

        return $query;
    }

    /**
     * @param  Collection<int, ScheduledJob>  $jobs
     * @return array<string, array<int, string>>
     */
    public function previewResolvedTargets(Collection $jobs): array
    {
        $resolved = [];

        foreach ($jobs as $job) {
            $resolved[$job->id] = $this->resolveTargetDeviceIds(
                $job->target_type,
                is_array($job->target_ids) ? $job->target_ids : [],
                $job->created_by_role,
                $job->created_by_user_id,
            );
        }

        return $resolved;
    }
}
