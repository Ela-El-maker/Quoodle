<?php

namespace App\Http\Controllers\Schedules;

use App\Http\Controllers\Controller;
use App\Models\ScheduledJob;
use App\Models\ScheduledJobRun;
use App\Models\User;
use App\Services\Scheduling\ScheduledExecutionService;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class ScheduleController extends Controller
{
    public function __construct(private readonly ScheduledExecutionService $scheduling)
    {
    }

    public function index(Request $request): JsonResponse
    {
        $this->scheduling->reconcileRuns();

        $jobs = $this->visibleJobsQuery($request)
            ->with(['creator:id,email', 'latestRun'])
            ->withCount([
                'runs as total_runs',
                'runs as success_runs' => fn (Builder $query): Builder => $query->where('status', 'success'),
                'runs as failed_runs' => fn (Builder $query): Builder => $query->where('status', 'failed'),
            ])
            ->orderByDesc('created_at')
            ->get();

        $resolvedTargets = $this->scheduling->previewResolvedTargets($jobs);

        return response()->json([
            'schedules' => $jobs->map(fn (ScheduledJob $job): array => $this->serializeJob($job, $resolvedTargets[$job->id] ?? [])),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        /** @var User|null $user */
        $user = $request->user();
        if (! $user) {
            return response()->json(['message' => 'unauthenticated'], 401);
        }

        $validator = Validator::make($request->all(), [
            'name' => ['required', 'string', 'max:190'],
            'method' => ['required', 'string', 'max:190'],
            'params' => ['present', 'array'],
            'target_type' => ['required', 'string', 'in:device,group,all'],
            'target_ids' => ['nullable', 'array'],
            'target_ids.*' => ['string', 'max:190'],
            'cron_expression' => ['required', 'string', 'max:128'],
            'timezone' => ['required', 'string', 'max:64'],
            'enabled' => ['nullable', 'boolean'],
        ]);

        if ($validator->fails()) {
            return response()->json([
                'message' => 'validation_error',
                'errors' => $validator->errors(),
            ], 422);
        }

        $payload = $validator->validated();
        $targetType = (string) $payload['target_type'];
        $targetIds = is_array($payload['target_ids'] ?? null) ? $payload['target_ids'] : [];

        if ($targetType !== 'all' && $targetIds === []) {
            return response()->json([
                'message' => 'validation_error',
                'errors' => ['target_ids' => ['target_ids are required for non-all schedules']],
            ], 422);
        }

        $cronExpression = trim((string) $payload['cron_expression']);
        $timezone = trim((string) $payload['timezone']);

        if (! $this->scheduling->isValidCron($cronExpression)) {
            return response()->json([
                'message' => 'validation_error',
                'errors' => ['cron_expression' => ['invalid cron expression']],
            ], 422);
        }

        if (! $this->scheduling->isValidTimezone($timezone)) {
            return response()->json([
                'message' => 'validation_error',
                'errors' => ['timezone' => ['invalid timezone identifier']],
            ], 422);
        }

        $method = trim((string) $payload['method']);
        $assessment = $this->scheduling->assessSchedulableMethod($method, (string) $user->role);
        if (! $assessment['ok']) {
            return response()->json([
                'message' => 'schedule_rejected',
                'reason' => $assessment['reason'],
            ], 422);
        }

        $definition = $assessment['definition'];
        $params = is_array($payload['params'] ?? null) ? $payload['params'] : [];
        $paramValidation = $definition?->validate($params) ?? ['valid' => false, 'errors' => ['unknown_command']];
        if (! $paramValidation['valid']) {
            return response()->json([
                'message' => 'validation_error',
                'errors' => ['params' => $paramValidation['errors']],
            ], 422);
        }

        $resolvedDeviceIds = $this->scheduling->resolveTargetDeviceIds($targetType, $targetIds, (string) $user->role, (string) $user->id);
        if ($resolvedDeviceIds === []) {
            return response()->json([
                'message' => 'validation_error',
                'errors' => ['target_ids' => ['no visible devices matched the selected target']],
            ], 422);
        }

        $enabled = (bool) ($payload['enabled'] ?? true);
        $nextRunAt = $enabled
            ? $this->scheduling->computeNextRunAt($cronExpression, $timezone, CarbonImmutable::now('UTC'))
            : null;

        $job = ScheduledJob::create([
            'created_by_user_id' => $user->id,
            'created_by_role' => (string) $user->role,
            'name' => trim((string) $payload['name']),
            'method' => $method,
            'params' => $params,
            'target_type' => $targetType,
            'target_ids' => $targetIds,
            'cron_expression' => $cronExpression,
            'timezone' => $timezone,
            'enabled' => $enabled,
            'next_run_at' => $nextRunAt,
        ]);

        $job->load(['creator:id,email', 'latestRun']);
        $job->setAttribute('total_runs', 0);
        $job->setAttribute('success_runs', 0);
        $job->setAttribute('failed_runs', 0);

        return response()->json([
            'schedule' => $this->serializeJob($job, $resolvedDeviceIds),
        ], 201);
    }

    public function update(Request $request, string $schedule_id): JsonResponse
    {
        $job = $this->visibleJob($request, $schedule_id);
        if (! $job) {
            return response()->json(['message' => 'not_found'], 404);
        }

        $validator = Validator::make($request->all(), [
            'name' => ['sometimes', 'string', 'max:190'],
            'method' => ['sometimes', 'string', 'max:190'],
            'params' => ['sometimes', 'array'],
            'target_type' => ['sometimes', 'string', 'in:device,group,all'],
            'target_ids' => ['sometimes', 'array'],
            'target_ids.*' => ['string', 'max:190'],
            'cron_expression' => ['sometimes', 'string', 'max:128'],
            'timezone' => ['sometimes', 'string', 'max:64'],
            'enabled' => ['sometimes', 'boolean'],
        ]);

        if ($validator->fails()) {
            return response()->json([
                'message' => 'validation_error',
                'errors' => $validator->errors(),
            ], 422);
        }

        $patch = $validator->validated();

        $method = array_key_exists('method', $patch) ? trim((string) $patch['method']) : (string) $job->method;
        $params = array_key_exists('params', $patch) && is_array($patch['params']) ? $patch['params'] : (is_array($job->params) ? $job->params : []);
        $targetType = array_key_exists('target_type', $patch) ? trim((string) $patch['target_type']) : (string) $job->target_type;
        $targetIds = array_key_exists('target_ids', $patch) && is_array($patch['target_ids']) ? $patch['target_ids'] : (is_array($job->target_ids) ? $job->target_ids : []);
        $cronExpression = array_key_exists('cron_expression', $patch) ? trim((string) $patch['cron_expression']) : (string) $job->cron_expression;
        $timezone = array_key_exists('timezone', $patch) ? trim((string) $patch['timezone']) : (string) $job->timezone;
        $enabled = array_key_exists('enabled', $patch) ? (bool) $patch['enabled'] : (bool) $job->enabled;

        if ($targetType !== 'all' && $targetIds === []) {
            return response()->json([
                'message' => 'validation_error',
                'errors' => ['target_ids' => ['target_ids are required for non-all schedules']],
            ], 422);
        }

        if (! $this->scheduling->isValidCron($cronExpression)) {
            return response()->json([
                'message' => 'validation_error',
                'errors' => ['cron_expression' => ['invalid cron expression']],
            ], 422);
        }

        if (! $this->scheduling->isValidTimezone($timezone)) {
            return response()->json([
                'message' => 'validation_error',
                'errors' => ['timezone' => ['invalid timezone identifier']],
            ], 422);
        }

        $assessment = $this->scheduling->assessSchedulableMethod($method, (string) $job->created_by_role);
        if (! $assessment['ok']) {
            return response()->json([
                'message' => 'schedule_rejected',
                'reason' => $assessment['reason'],
            ], 422);
        }

        $definition = $assessment['definition'];
        $paramValidation = $definition?->validate($params) ?? ['valid' => false, 'errors' => ['unknown_command']];
        if (! $paramValidation['valid']) {
            return response()->json([
                'message' => 'validation_error',
                'errors' => ['params' => $paramValidation['errors']],
            ], 422);
        }

        $resolvedDeviceIds = $this->scheduling->resolveTargetDeviceIds(
            $targetType,
            $targetIds,
            (string) $job->created_by_role,
            $job->created_by_user_id,
        );

        if ($resolvedDeviceIds === []) {
            return response()->json([
                'message' => 'validation_error',
                'errors' => ['target_ids' => ['no visible devices matched the selected target']],
            ], 422);
        }

        $nextRunAt = $job->next_run_at;
        if (! $enabled) {
            $nextRunAt = null;
        } else {
            $scheduleChanged =
                array_key_exists('enabled', $patch)
                || array_key_exists('cron_expression', $patch)
                || array_key_exists('timezone', $patch);

            if ($scheduleChanged || ! $nextRunAt || $nextRunAt->lessThanOrEqualTo(now('UTC'))) {
                $nextRunAt = $this->scheduling->computeNextRunAt($cronExpression, $timezone, CarbonImmutable::now('UTC'));
            }
        }

        $job->fill([
            'name' => array_key_exists('name', $patch) ? trim((string) $patch['name']) : $job->name,
            'method' => $method,
            'params' => $params,
            'target_type' => $targetType,
            'target_ids' => $targetIds,
            'cron_expression' => $cronExpression,
            'timezone' => $timezone,
            'enabled' => $enabled,
            'next_run_at' => $nextRunAt,
        ]);
        $job->save();

        $job->load(['creator:id,email', 'latestRun']);
        $job->loadCount([
            'runs as total_runs',
            'runs as success_runs' => fn (Builder $query): Builder => $query->where('status', 'success'),
            'runs as failed_runs' => fn (Builder $query): Builder => $query->where('status', 'failed'),
        ]);

        return response()->json([
            'schedule' => $this->serializeJob($job, $resolvedDeviceIds),
        ]);
    }

    public function destroy(Request $request, string $schedule_id): JsonResponse
    {
        $job = $this->visibleJob($request, $schedule_id);
        if (! $job) {
            return response()->json(['message' => 'not_found'], 404);
        }

        $job->delete();

        return response()->json(['status' => 'deleted']);
    }

    public function runNow(Request $request, string $schedule_id): JsonResponse
    {
        $job = $this->visibleJob($request, $schedule_id);
        if (! $job) {
            return response()->json(['message' => 'not_found'], 404);
        }

        $run = $this->scheduling->runNow($job);

        return response()->json([
            'run' => [
                'run_id' => $run->id,
                'job_id' => $run->job_id,
                'status' => $run->status,
                'scheduled_for' => $run->scheduled_for?->toIso8601String(),
            ],
        ], 202);
    }

    private function visibleJobsQuery(Request $request): Builder
    {
        /** @var User|null $user */
        $user = $request->user();
        $query = ScheduledJob::query();

        if (! $user || $user->role !== User::ROLE_ADMIN) {
            $query->where('created_by_user_id', $user?->id);
        }

        return $query;
    }

    private function visibleJob(Request $request, string $scheduleId): ?ScheduledJob
    {
        return $this->visibleJobsQuery($request)
            ->where('id', $scheduleId)
            ->first();
    }

    /**
     * @param  array<int, string>  $resolvedDeviceIds
     * @return array<string, mixed>
     */
    private function serializeJob(ScheduledJob $job, array $resolvedDeviceIds): array
    {
        /** @var ScheduledJobRun|null $latestRun */
        $latestRun = $job->latestRun;

        return [
            'id' => $job->id,
            'name' => $job->name,
            'method' => $job->method,
            'params' => is_array($job->params) ? $job->params : [],
            'target_type' => $job->target_type,
            'target_ids' => is_array($job->target_ids) ? $job->target_ids : [],
            'resolved_device_ids' => $resolvedDeviceIds,
            'cron_expression' => $job->cron_expression,
            'timezone' => $job->timezone,
            'enabled' => (bool) $job->enabled,
            'last_run_at' => optional($job->last_run_at)?->toIso8601String(),
            'next_run_at' => optional($job->next_run_at)?->toIso8601String(),
            'created_at' => optional($job->created_at)?->toIso8601String(),
            'created_by_user_id' => $job->created_by_user_id,
            'created_by_role' => $job->created_by_role,
            'created_by_email' => $job->creator?->email,
            'total_runs' => (int) ($job->total_runs ?? 0),
            'success_runs' => (int) ($job->success_runs ?? 0),
            'failed_runs' => (int) ($job->failed_runs ?? 0),
            'last_run_status' => $latestRun?->status,
        ];
    }
}
