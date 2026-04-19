<?php

namespace App\Services\SystemHealth;

use App\Models\Alert;
use App\Models\Command;
use App\Models\Device;
use App\Models\IntegrationWebhookDelivery;
use App\Models\TelemetryEvent;
use Carbon\Carbon;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Schema;

class SystemHealthService
{
    /**
     * @return array<string,mixed>
     */
    public function overview(): array
    {
        $components = collect($this->components());
        $counts = [
            'healthy' => (int) $components->where('status', 'healthy')->count(),
            'degraded' => (int) $components->where('status', 'degraded')->count(),
            'offline' => (int) $components->where('status', 'offline')->count(),
        ];

        $overall = 'healthy';
        if ($counts['offline'] > 0) {
            $overall = 'offline';
        } elseif ($counts['degraded'] > 0) {
            $overall = 'degraded';
        }

        $webhookStats = $this->webhookStats();
        $pipelineStats = $this->pipelineStats();
        $infraStats = $this->infraStats();

        return [
            'generated_at' => now()->toIso8601String(),
            'overall_status' => $overall,
            'component_counts' => $counts,
            'infra' => $infraStats,
            'pipeline' => $pipelineStats,
            'webhooks' => $webhookStats,
        ];
    }

    /**
     * @return array<int,array<string,mixed>>
     */
    public function components(): array
    {
        $components = [];
        $components[] = $this->dbComponent();
        $components[] = $this->cacheComponent();
        $components[] = $this->gatewayComponent();
        $components[] = $this->queueComponent();
        $components[] = $this->schedulerComponent();
        $components[] = $this->workerComponent();
        $components[] = $this->webhookComponent();
        $components[] = $this->pipelineComponent();
        $components[] = $this->fleetComponent();

        return $components;
    }

    /**
     * @return array<int,array<string,mixed>>
     */
    public function timeseries(int $windowMinutes = 360, int $bucketMinutes = 5): array
    {
        $windowMinutes = max(5, min($windowMinutes, 60 * 24 * 7));
        $bucketMinutes = max(1, min($bucketMinutes, 60));
        $to = now()->utc();
        $from = $to->copy()->subMinutes($windowMinutes);

        $points = $this->initBuckets($from, $to, $bucketMinutes);

        $this->accumulateByTimestamp(
            $points,
            Command::query()->where('queued_at', '>=', $from)->get(['queued_at', 'state']),
            'queued_at',
            $bucketMinutes,
            static function (array &$bucket, array $row): void {
                $state = (string) ($row['state'] ?? '');
                if ($state === 'completed') {
                    $bucket['commands_completed']++;
                } elseif ($state === 'failed') {
                    $bucket['commands_failed']++;
                }
            }
        );

        $this->accumulateByTimestamp(
            $points,
            IntegrationWebhookDelivery::query()
                ->where('created_at', '>=', $from)
                ->get(['created_at', 'status']),
            'created_at',
            $bucketMinutes,
            static function (array &$bucket, array $row): void {
                $status = (string) ($row['status'] ?? '');
                if ($status === IntegrationWebhookDelivery::STATUS_SENT) {
                    $bucket['webhook_sent']++;
                } elseif ($status === IntegrationWebhookDelivery::STATUS_DEAD_LETTER) {
                    $bucket['webhook_dead_letter']++;
                } elseif ($status === IntegrationWebhookDelivery::STATUS_RETRYING) {
                    $bucket['webhook_retrying']++;
                }
            }
        );

        $this->accumulateByTimestamp(
            $points,
            TelemetryEvent::query()
                ->where('timestamp', '>=', $from)
                ->get(['timestamp']),
            'timestamp',
            $bucketMinutes,
            static function (array &$bucket): void {
                $bucket['telemetry_ingest']++;
            }
        );

        $this->accumulateByTimestamp(
            $points,
            Alert::query()
                ->where('timestamp', '>=', $from)
                ->where('severity', 'critical')
                ->get(['timestamp']),
            'timestamp',
            $bucketMinutes,
            static function (array &$bucket): void {
                $bucket['critical_alerts']++;
            }
        );

        return array_values($points);
    }

    /**
     * @return array<int,array<string,mixed>>
     */
    public function events(int $limit = 100, int $windowMinutes = 180): array
    {
        $limit = max(1, min($limit, 500));
        $windowMinutes = max(5, min($windowMinutes, 60 * 24 * 7));
        $from = now()->subMinutes($windowMinutes);
        $events = [];

        $failedCommands = Command::query()
            ->where('state', 'failed')
            ->where(function ($query) use ($from): void {
                $query->where('completed_at', '>=', $from)
                    ->orWhere(function ($q) use ($from): void {
                        $q->whereNull('completed_at')->where('updated_at', '>=', $from);
                    });
            })
            ->orderByDesc('completed_at')
            ->limit($limit)
            ->get(['id', 'device_id', 'method', 'reason', 'error_code', 'completed_at', 'updated_at']);
        foreach ($failedCommands as $command) {
            $events[] = [
                'type' => 'command.failed',
                'timestamp' => optional($command->completed_at ?? $command->updated_at)?->toIso8601String(),
                'severity' => 'warning',
                'title' => 'Command failure',
                'detail' => sprintf(
                    '%s on %s failed: %s',
                    (string) $command->method,
                    (string) $command->device_id,
                    (string) ($command->reason ?? 'unknown'),
                ),
                'meta' => [
                    'command_id' => $command->id,
                    'device_id' => $command->device_id,
                    'error_code' => $command->error_code,
                ],
            ];
        }

        $deadDeliveries = IntegrationWebhookDelivery::query()
            ->where('status', IntegrationWebhookDelivery::STATUS_DEAD_LETTER)
            ->where('updated_at', '>=', $from)
            ->orderByDesc('updated_at')
            ->limit($limit)
            ->get(['id', 'endpoint_id', 'event_type', 'last_error', 'updated_at']);
        foreach ($deadDeliveries as $delivery) {
            $events[] = [
                'type' => 'webhook.dead_letter',
                'timestamp' => $delivery->updated_at?->toIso8601String(),
                'severity' => 'warning',
                'title' => 'Webhook dead-letter',
                'detail' => sprintf(
                    '%s delivery to endpoint %s failed permanently',
                    (string) $delivery->event_type,
                    (string) $delivery->endpoint_id,
                ),
                'meta' => [
                    'delivery_id' => $delivery->id,
                    'endpoint_id' => $delivery->endpoint_id,
                    'error' => $delivery->last_error,
                ],
            ];
        }

        $criticalAlerts = Alert::query()
            ->where('severity', 'critical')
            ->where('timestamp', '>=', $from)
            ->orderByDesc('timestamp')
            ->limit($limit)
            ->get(['alert_id', 'device_id', 'message', 'timestamp']);
        foreach ($criticalAlerts as $alert) {
            $events[] = [
                'type' => 'alert.critical',
                'timestamp' => $alert->timestamp?->toIso8601String(),
                'severity' => 'critical',
                'title' => 'Critical alert',
                'detail' => (string) ($alert->message ?? 'Critical alert raised'),
                'meta' => [
                    'alert_id' => $alert->alert_id,
                    'device_id' => $alert->device_id,
                ],
            ];
        }

        usort($events, static function (array $a, array $b): int {
            $at = strtotime((string) ($a['timestamp'] ?? '')) ?: 0;
            $bt = strtotime((string) ($b['timestamp'] ?? '')) ?: 0;
            return $bt <=> $at;
        });

        return array_slice($events, 0, $limit);
    }

    /**
     * @return array<string,mixed>
     */
    private function dbComponent(): array
    {
        $start = microtime(true);
        try {
            DB::select('SELECT 1 as ok');
            $latency = (int) round((microtime(true) - $start) * 1000);
            return $this->component('db', 'Primary Database', 'infrastructure', 'healthy', $latency, [
                'connection' => config('database.default'),
            ]);
        } catch (\Throwable $e) {
            return $this->component('db', 'Primary Database', 'infrastructure', 'offline', null, [
                'error' => $e->getMessage(),
            ]);
        }
    }

    /**
     * @return array<string,mixed>
     */
    private function cacheComponent(): array
    {
        $start = microtime(true);
        try {
            $probeKey = 'system_health:cache_probe';
            $probeValue = (string) now()->timestamp;
            Cache::put($probeKey, $probeValue, 10);
            $observed = (string) Cache::get($probeKey, '');
            $latency = (int) round((microtime(true) - $start) * 1000);

            return $this->component(
                'cache',
                'Cache/Redis',
                'infrastructure',
                $observed === $probeValue ? 'healthy' : 'degraded',
                $latency,
                ['store' => config('cache.default')]
            );
        } catch (\Throwable $e) {
            return $this->component('cache', 'Cache/Redis', 'infrastructure', 'offline', null, [
                'error' => $e->getMessage(),
            ]);
        }
    }

    /**
     * @return array<string,mixed>
     */
    private function gatewayComponent(): array
    {
        $gatewayHealthUrl = $this->gatewayHealthUrl();
        $start = microtime(true);

        try {
            $response = Http::timeout(3)->acceptJson()->get($gatewayHealthUrl);
            $latency = (int) round((microtime(true) - $start) * 1000);
            if (! $response->ok()) {
                return $this->component('gateway', 'Gateway API', 'infrastructure', 'degraded', $latency, [
                    'url' => $gatewayHealthUrl,
                    'http_status' => $response->status(),
                ]);
            }

            return $this->component('gateway', 'Gateway API', 'infrastructure', 'healthy', $latency, [
                'url' => $gatewayHealthUrl,
                'http_status' => $response->status(),
                'payload' => $response->json(),
            ]);
        } catch (\Throwable $e) {
            return $this->component('gateway', 'Gateway API', 'infrastructure', 'offline', null, [
                'url' => $gatewayHealthUrl,
                'error' => $e->getMessage(),
            ]);
        }
    }

    /**
     * @return array<string,mixed>
     */
    private function queueComponent(): array
    {
        try {
            $pending = Schema::hasTable('jobs') ? (int) DB::table('jobs')->count() : 0;
            $failed = Schema::hasTable('failed_jobs') ? (int) DB::table('failed_jobs')->count() : 0;
            $status = $failed > 0 ? 'degraded' : 'healthy';

            return $this->component('queue', 'Queue Runtime', 'runtime', $status, null, [
                'driver' => config('queue.default'),
                'pending_jobs' => $pending,
                'failed_jobs' => $failed,
            ]);
        } catch (\Throwable $e) {
            return $this->component('queue', 'Queue Runtime', 'runtime', 'offline', null, [
                'error' => $e->getMessage(),
            ]);
        }
    }

    /**
     * @return array<string,mixed>
     */
    private function schedulerComponent(): array
    {
        $heartbeatIso = Cache::get('scheduler:last_heartbeat');
        $status = 'degraded';
        $ageSeconds = null;
        if (is_string($heartbeatIso) && $heartbeatIso !== '') {
            try {
                $ageSeconds = now()->diffInSeconds(Carbon::parse($heartbeatIso), false) * -1;
                $status = $ageSeconds <= 120 ? 'healthy' : 'degraded';
            } catch (\Throwable) {
                $status = 'degraded';
            }
        }

        return $this->component('scheduler', 'Scheduler', 'runtime', $status, null, [
            'last_heartbeat' => $heartbeatIso,
            'heartbeat_age_seconds' => $ageSeconds,
        ]);
    }

    /**
     * @return array<string,mixed>
     */
    private function workerComponent(): array
    {
        $latestCommand = Command::query()->max('updated_at');
        $latestTelemetry = TelemetryEvent::query()->max('timestamp');
        $latest = collect([$latestCommand, $latestTelemetry])
            ->filter()
            ->map(fn ($value) => Carbon::parse((string) $value))
            ->sortDesc()
            ->first();

        if (! $latest) {
            return $this->component('workers', 'Workers', 'runtime', 'degraded', null, [
                'last_activity_at' => null,
            ]);
        }

        $age = now()->diffInSeconds($latest);
        $status = $age <= 120 ? 'healthy' : ($age <= 600 ? 'degraded' : 'offline');

        return $this->component('workers', 'Workers', 'runtime', $status, null, [
            'last_activity_at' => $latest->toIso8601String(),
            'last_activity_age_seconds' => $age,
        ]);
    }

    /**
     * @return array<string,mixed>
     */
    private function webhookComponent(): array
    {
        $stats = $this->webhookStats();
        $status = $stats['dead_letter'] > 0 ? 'degraded' : 'healthy';

        return $this->component('webhooks', 'Webhook Delivery Runtime', 'integrations', $status, null, $stats);
    }

    /**
     * @return array<string,mixed>
     */
    private function pipelineComponent(): array
    {
        $stats = $this->pipelineStats();
        $status = 'healthy';
        if ($stats['replay_rejections_1h'] > 0 || $stats['stuck_commands'] > 0) {
            $status = 'degraded';
        }

        return $this->component('pipeline', 'Command + Telemetry Pipeline', 'pipeline', $status, null, $stats);
    }

    /**
     * @return array<string,mixed>
     */
    private function fleetComponent(): array
    {
        $total = (int) Device::query()->count();
        $offline = (int) Device::query()->where('lifecycle_state', 'offline')->count();
        $status = $total > 0 && $offline === $total ? 'offline' : ($offline > 0 ? 'degraded' : 'healthy');

        return $this->component('fleet', 'Fleet Presence', 'fleet', $status, null, [
            'total_devices' => $total,
            'offline_devices' => $offline,
            'online_devices' => max(0, $total - $offline),
        ]);
    }

    /**
     * @return array<string,mixed>
     */
    private function webhookStats(): array
    {
        $base = IntegrationWebhookDelivery::query()->where('created_at', '>=', now()->subDay());

        return [
            'sent' => (clone $base)->where('status', IntegrationWebhookDelivery::STATUS_SENT)->count(),
            'retrying' => (clone $base)->where('status', IntegrationWebhookDelivery::STATUS_RETRYING)->count(),
            'dead_letter' => (clone $base)->where('status', IntegrationWebhookDelivery::STATUS_DEAD_LETTER)->count(),
            'avg_latency_ms' => (float) ((clone $base)->whereNotNull('latency_ms')->avg('latency_ms') ?? 0),
        ];
    }

    /**
     * @return array<string,mixed>
     */
    private function pipelineStats(): array
    {
        $criticalAlertsQuery = Alert::query()->where('severity', 'critical');
        if (Schema::hasColumn('alerts', 'acknowledged_at')) {
            $criticalAlertsQuery->where(function ($q): void {
                $q->whereNull('acknowledged_at')->orWhere('acknowledged', false);
            });
        } else {
            $criticalAlertsQuery->where(function ($q): void {
                $q->where('acknowledged', false)->orWhereNull('acknowledged');
            });
        }

        return [
            'stuck_commands' => (int) Command::query()
                ->whereIn('state', ['queued', 'dispatched', 'sent', 'ack_received'])
                ->where('queued_at', '<=', now()->subMinutes(10))
                ->count(),
            'replay_rejections_1h' => (int) Command::query()
                ->where('reason', 'SEQ_REPLAY')
                ->where('updated_at', '>=', now()->subHour())
                ->count(),
            'critical_alerts_open' => (int) $criticalAlertsQuery->count(),
            'telemetry_events_1h' => (int) TelemetryEvent::query()
                ->where('timestamp', '>=', now()->subHour())
                ->count(),
            'compliance_drift_devices' => (int) Device::query()
                ->where(function ($q): void {
                    $q->whereNull('compliance_status')->orWhere('compliance_status', '!=', 'compliant');
                })
                ->count(),
        ];
    }

    /**
     * @return array<string,mixed>
     */
    private function infraStats(): array
    {
        $diskTotal = @disk_total_space(base_path());
        $diskFree = @disk_free_space(base_path());
        $diskUsedPercent = null;
        if (is_numeric($diskTotal) && is_numeric($diskFree) && (float) $diskTotal > 0) {
            $diskUsedPercent = round((1 - ((float) $diskFree / (float) $diskTotal)) * 100, 2);
        }

        return [
            'pending_jobs' => Schema::hasTable('jobs') ? (int) DB::table('jobs')->count() : 0,
            'failed_jobs' => Schema::hasTable('failed_jobs') ? (int) DB::table('failed_jobs')->count() : 0,
            'disk_used_percent' => $diskUsedPercent,
            'memory_usage_mb' => round(memory_get_usage(true) / (1024 * 1024), 2),
            'memory_peak_mb' => round(memory_get_peak_usage(true) / (1024 * 1024), 2),
            'queue_driver' => config('queue.default'),
            'cache_store' => config('cache.default'),
        ];
    }

    private function gatewayHealthUrl(): string
    {
        $base = (string) config('services.fastapi.base_url', 'http://localhost:8000/api/v1');
        $base = preg_replace('#/api/v1/?$#', '', rtrim($base, '/')) ?: 'http://localhost:8000';
        return rtrim($base, '/').'/health';
    }

    /**
     * @param  array<string,mixed>  $meta
     * @return array<string,mixed>
     */
    private function component(
        string $id,
        string $name,
        string $category,
        string $status,
        ?int $latencyMs,
        array $meta = [],
    ): array {
        return [
            'id' => $id,
            'name' => $name,
            'category' => $category,
            'status' => $status,
            'latency_ms' => $latencyMs,
            'checked_at' => now()->toIso8601String(),
            'meta' => $meta,
        ];
    }

    /**
     * @return array<string,array<string,mixed>>
     */
    private function initBuckets(Carbon $from, Carbon $to, int $bucketMinutes): array
    {
        $cursor = $from->copy()->second(0);
        $cursor->minute((int) floor($cursor->minute / $bucketMinutes) * $bucketMinutes);
        $buckets = [];
        while ($cursor->lessThanOrEqualTo($to)) {
            $key = $cursor->toIso8601String();
            $buckets[$key] = [
                'timestamp' => $key,
                'commands_completed' => 0,
                'commands_failed' => 0,
                'telemetry_ingest' => 0,
                'webhook_sent' => 0,
                'webhook_retrying' => 0,
                'webhook_dead_letter' => 0,
                'critical_alerts' => 0,
            ];
            $cursor = $cursor->copy()->addMinutes($bucketMinutes);
        }
        return $buckets;
    }

    /**
     * @param  Collection<int,mixed>  $rows
     * @param  callable(array<string,mixed>&, array<string,mixed>):void  $accumulator
     * @param  string  $timestampKey
     * @param  array<string,array<string,mixed>>  $buckets
     */
    private function accumulateByTimestamp(
        array &$buckets,
        Collection $rows,
        string $timestampKey,
        int $bucketMinutes,
        callable $accumulator,
    ): void {
        foreach ($rows as $row) {
            $arrayRow = is_array($row) ? $row : (method_exists($row, 'toArray') ? $row->toArray() : []);
            $raw = $arrayRow[$timestampKey] ?? null;
            if (! $raw) {
                continue;
            }
            try {
                $ts = Carbon::parse((string) $raw)->second(0);
            } catch (\Throwable) {
                continue;
            }

            $ts->minute((int) floor($ts->minute / $bucketMinutes) * $bucketMinutes);
            $bucketKey = $ts->toIso8601String();
            if (! isset($buckets[$bucketKey])) {
                continue;
            }

            $accumulator($buckets[$bucketKey], $arrayRow);
        }
    }
}
