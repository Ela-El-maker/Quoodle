<?php

namespace App\Http\Controllers\Schedules;

use App\Http\Controllers\Controller;
use App\Models\ScheduledJob;
use App\Models\ScheduledJobRunItem;
use App\Models\User;
use App\Services\Scheduling\ScheduledExecutionService;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ScheduleRunsController extends Controller
{
    public function __construct(private readonly ScheduledExecutionService $scheduling)
    {
    }

    public function index(Request $request): JsonResponse
    {
        /** @var User|null $user */
        $user = $request->user();
        if (! $user) {
            return response()->json(['message' => 'unauthenticated'], 401);
        }

        $this->scheduling->reconcileRuns();

        $limit = min(max((int) $request->query('limit', 200), 1), 500);
        $jobFilter = trim((string) $request->query('job_id', ''));

        $visibleJobIds = ScheduledJob::query()
            ->when($user->role !== User::ROLE_ADMIN, fn (Builder $query): Builder => $query->where('created_by_user_id', $user->id))
            ->when($jobFilter !== '', fn (Builder $query): Builder => $query->where('id', $jobFilter))
            ->pluck('id');

        if ($visibleJobIds->isEmpty()) {
            return response()->json(['runs' => []]);
        }

        $items = ScheduledJobRunItem::query()
            ->whereHas('run', fn (Builder $query): Builder => $query->whereIn('job_id', $visibleJobIds))
            ->with([
                'run.job:id,name',
                'command:id,state,execution_state,queued_at,completed_at,error_message,reason',
                'device:device_id,device_name',
            ])
            ->orderByDesc('started_at')
            ->orderByDesc('id')
            ->limit($limit)
            ->get();

        return response()->json([
            'runs' => $items->map(fn (ScheduledJobRunItem $item): array => $this->serializeItem($item)),
        ]);
    }

    /**
     * @return array<string, mixed>
     */
    private function serializeItem(ScheduledJobRunItem $item): array
    {
        $derived = $this->deriveStatus($item);
        $startedAt = $item->started_at ?? $item->created_at;
        $finishedAt = $item->finished_at ?? $item->command?->completed_at;

        return [
            'id' => $item->id,
            'run_id' => $item->run_id,
            'job_id' => $item->run?->job_id,
            'job_name' => $item->run?->job?->name,
            'batch_id' => $item->run_id,
            'device_id' => $item->device_id,
            'hostname' => $item->device?->device_name ?: $item->device_id,
            'status' => $derived['status'],
            'started_at' => optional($startedAt)?->toIso8601String(),
            'completed_at' => optional($finishedAt)?->toIso8601String(),
            'duration_seconds' => $this->durationSeconds($startedAt?->timestamp, $finishedAt?->timestamp),
            'command_id' => $item->command_id,
            'error_message' => $derived['error_message'],
            'scheduled_for' => optional($item->run?->scheduled_for)?->toIso8601String(),
        ];
    }

    /**
     * @return array{status: string, error_message: string|null}
     */
    private function deriveStatus(ScheduledJobRunItem $item): array
    {
        if ($item->command) {
            $state = (string) ($item->command->execution_state ?: $item->command->state ?: 'queued');

            if (in_array($state, ['completed'], true)) {
                return ['status' => 'success', 'error_message' => null];
            }

            if (in_array($state, ['failed', 'expired', 'rejected'], true)) {
                return [
                    'status' => 'failed',
                    'error_message' => $item->command->error_message ?: $item->command->reason ?: $item->error_message,
                ];
            }

            return ['status' => 'running', 'error_message' => null];
        }

        if ($item->status === 'failed') {
            return ['status' => 'failed', 'error_message' => $item->error_message];
        }

        if ($item->status === 'success') {
            return ['status' => 'success', 'error_message' => null];
        }

        return ['status' => 'running', 'error_message' => null];
    }

    private function durationSeconds(?int $startTs, ?int $endTs): ?int
    {
        if (! $startTs || ! $endTs || $endTs < $startTs) {
            return null;
        }

        return $endTs - $startTs;
    }
}
