<?php

namespace App\Services\Telemetry;

use App\Models\DeviceTelemetryLatest;
use App\Models\Device;
use App\Models\TelemetryEvent;
use App\Models\TelemetryIngestError;
use App\Models\TelemetryRollup;
use App\Models\TelemetrySnapshot;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Log;
use Throwable;

class TelemetryIngestService
{
    public function ingest(string $deviceId, array $payload): array
    {
        try {
            return DB::transaction(function () use ($deviceId, $payload): array {
                $timestamp = $this->parseTimestamp($payload['timestamp'] ?? null);
                $rollup = is_array($payload['rollup'] ?? null) ? $payload['rollup'] : [];
                $metrics = is_array($payload['metrics'] ?? null) ? $payload['metrics'] : [];
                $scope = (string) ($payload['telemetry_scope'] ?? ($rollup['kernel_event'] ?? null ? 'kernel_event' : 'telemetry_extended'));
                $schemaVersion = (string) ($payload['schema_version'] ?? 'v1');
                $sessionId = isset($payload['session_id']) ? (string) $payload['session_id'] : null;
                $seq = isset($payload['seq']) ? (int) $payload['seq'] : null;
                $policyHash = $this->asNullableString($rollup['policy_hash'] ?? $payload['policy_hash'] ?? null);
                $riskScore = $this->toFloat($rollup['risk_score_avg'] ?? $metrics['risk_score'] ?? null);
                $presenceState = $this->normalizePresenceState($this->asNullableString($rollup['presence_state'] ?? $payload['presence_state'] ?? null));
                $connectionMode = $this->asNullableString($rollup['connection_mode'] ?? $payload['connection_mode'] ?? null);
                $maskedFields = is_array($payload['masked_fields'] ?? null) ? $payload['masked_fields'] : [];

                $canonicalMetrics = $this->normalizeMetrics($rollup, $metrics);
                $telemetryOsBuild = $this->asNullableString($canonicalMetrics['os_build'] ?? null);

                $event = TelemetryEvent::create([
                    'device_id' => $deviceId,
                    'telemetry_scope' => $scope,
                    'schema_version' => $schemaVersion,
                    'session_id' => $sessionId,
                    'seq' => $seq,
                    'timestamp' => $timestamp,
                    'metrics' => $canonicalMetrics,
                    'masked_fields' => $maskedFields,
                    'policy_hash' => $policyHash,
                    'risk_score' => $riskScore,
                    'presence_state' => $presenceState,
                    'connection_mode' => $connectionMode,
                    'source' => (string) ($payload['source'] ?? 'gateway'),
                ]);

                DeviceTelemetryLatest::updateOrCreate(
                    ['device_id' => $deviceId],
                    [
                        'telemetry_scope' => $scope,
                        'schema_version' => $schemaVersion,
                        'session_id' => $sessionId,
                        'seq' => $seq,
                        'timestamp' => $timestamp,
                        'metrics' => $canonicalMetrics,
                        'masked_fields' => $maskedFields,
                        'policy_hash' => $policyHash,
                        'risk_score' => $riskScore,
                        'presence_state' => $presenceState,
                        'connection_mode' => $connectionMode,
                        'updated_at' => now(),
                    ]
                );

                $snapshot = TelemetrySnapshot::create([
                    'device_id' => $deviceId,
                    'timestamp' => $timestamp,
                    'metrics' => $canonicalMetrics,
                ]);

                $this->upsertRollup($deviceId, $timestamp, $canonicalMetrics, $presenceState);

                $device = Device::query()->where('device_id', $deviceId)->first();
                $deviceUpdate = [
                    'last_seen' => $timestamp,
                    'risk_score' => $riskScore,
                    'reported_policy_hash' => $policyHash,
                ];
                if ($telemetryOsBuild) {
                    $deviceUpdate['os_build'] = $telemetryOsBuild;
                }
                if ($presenceState) {
                    $deviceUpdate['lifecycle_state'] = $this->presenceToLifecycleState($presenceState);
                }
                if ($device) {
                    $priorOsBuild = $this->asNullableString($device->os_build);
                    Device::where('device_id', $deviceId)->update($deviceUpdate);
                    if ($telemetryOsBuild && $priorOsBuild && $priorOsBuild !== $telemetryOsBuild) {
                        Cache::add('telemetry:divergence:os_build', 0, now()->addDay());
                        Cache::increment('telemetry:divergence:os_build');
                        Log::warning('telemetry.os_build_divergence_reconciled', [
                            'device_id' => $deviceId,
                            'previous_os_build' => $priorOsBuild,
                            'telemetry_os_build' => $telemetryOsBuild,
                            'session_id' => $sessionId,
                            'seq' => $seq,
                        ]);
                    }
                } else {
                    Device::where('device_id', $deviceId)->update($deviceUpdate);
                }

                Cache::add('telemetry:ingest:accepted', 0, now()->addDay());
                Cache::increment('telemetry:ingest:accepted');
                Log::debug('telemetry.ingest.accepted', [
                    'device_id' => $deviceId,
                    'scope' => $scope,
                    'schema_version' => $schemaVersion,
                    'session_id' => $sessionId,
                    'seq' => $seq,
                    'presence_state' => $presenceState,
                    'connection_mode' => $connectionMode,
                    'resolved_os_build' => $telemetryOsBuild,
                ]);

                return [
                    'status' => 'ingested',
                    'event_id' => $event->id,
                    'snapshot_id' => $snapshot->id ?? null,
                    'timestamp' => optional($timestamp)->toIso8601String(),
                    'presence_state' => $presenceState,
                ];
            });
        } catch (Throwable $e) {
            TelemetryIngestError::create([
                'device_id' => $deviceId,
                'timestamp' => now(),
                'reason' => 'ingest_exception',
                'details' => [
                    'message' => $e->getMessage(),
                    'payload' => $payload,
                ],
                'source' => (string) ($payload['source'] ?? 'gateway'),
            ]);

            Cache::add('telemetry:ingest:rejected', 0, now()->addDay());
            Cache::increment('telemetry:ingest:rejected');
            Log::warning('telemetry.ingest.rejected', [
                'device_id' => $deviceId,
                'reason' => 'ingest_exception',
                'message' => $e->getMessage(),
            ]);

            return [
                'status' => 'rejected',
                'reason' => 'ingest_exception',
                'timestamp' => now()->toIso8601String(),
            ];
        }
    }

    private function normalizeMetrics(array $rollup, array $metrics): array
    {
        $normalized = [
            'cpu' => $this->toFloat($metrics['cpu'] ?? $rollup['avg_cpu'] ?? null),
            'ram' => $this->toFloat($metrics['ram'] ?? $rollup['avg_ram'] ?? null),
            'disk_usage' => $this->toFloat($metrics['disk_usage'] ?? $rollup['avg_disk'] ?? null),
            'network_tx' => $this->toFloat($metrics['network_tx'] ?? $rollup['avg_tx'] ?? null),
            'network_rx' => $this->toFloat($metrics['network_rx'] ?? $rollup['avg_rx'] ?? null),
            'risk_score' => $this->toFloat($metrics['risk_score'] ?? $rollup['risk_score_avg'] ?? null),
            'policy_hash' => $this->asNullableString($metrics['policy_hash'] ?? $rollup['policy_hash'] ?? null),
            'kernel_event' => is_array($metrics['kernel_event'] ?? null) ? $metrics['kernel_event'] : ($rollup['kernel_event'] ?? null),
        ];

        foreach ($metrics as $key => $value) {
            if (! array_key_exists($key, $normalized)) {
                $normalized[$key] = $value;
            }
        }

        return $normalized;
    }

    private function upsertRollup(string $deviceId, Carbon $timestamp, array $metrics, ?string $presenceState): void
    {
        $bucketStart = $timestamp->copy()->second(0)->minute((int) (floor($timestamp->minute / 5) * 5));
        $rollup = TelemetryRollup::firstOrNew([
            'device_id' => $deviceId,
            'bucket_start' => $bucketStart,
            'bucket_minutes' => 5,
        ]);

        $prevSamples = (int) ($rollup->samples ?? 0);
        $nextSamples = $prevSamples + 1;
        $rollup->samples = $nextSamples;
        $rollup->avg_cpu = $this->weightedAvg($rollup->avg_cpu, $prevSamples, $this->toFloat($metrics['cpu'] ?? null));
        $rollup->avg_ram = $this->weightedAvg($rollup->avg_ram, $prevSamples, $this->toFloat($metrics['ram'] ?? null));
        $rollup->avg_disk_usage = $this->weightedAvg($rollup->avg_disk_usage, $prevSamples, $this->toFloat($metrics['disk_usage'] ?? null));
        $rollup->avg_network_tx = $this->weightedAvg($rollup->avg_network_tx, $prevSamples, $this->toFloat($metrics['network_tx'] ?? null));
        $rollup->avg_network_rx = $this->weightedAvg($rollup->avg_network_rx, $prevSamples, $this->toFloat($metrics['network_rx'] ?? null));
        $rollup->avg_risk_score = $this->weightedAvg($rollup->avg_risk_score, $prevSamples, $this->toFloat($metrics['risk_score'] ?? null));
        $candidateCpu = $this->toFloat($metrics['cpu'] ?? null);
        if ($candidateCpu !== null) {
            $existingMax = $this->toFloat($rollup->max_cpu);
            $rollup->max_cpu = $existingMax === null ? $candidateCpu : max($existingMax, $candidateCpu);
        }
        $rollup->presence_state = $presenceState;
        $rollup->save();
    }

    private function weightedAvg(mixed $existing, int $samples, ?float $next): ?float
    {
        if ($next === null) {
            return $this->toFloat($existing);
        }
        $existingVal = $this->toFloat($existing);
        if ($samples <= 0 || $existingVal === null) {
            return $next;
        }

        return (($existingVal * $samples) + $next) / ($samples + 1);
    }

    private function parseTimestamp(mixed $value): Carbon
    {
        if (is_string($value) && trim($value) !== '') {
            try {
                return Carbon::parse($value)->utc();
            } catch (Throwable $e) {
                // fall through
            }
        }
        return now()->utc();
    }

    private function asNullableString(mixed $value): ?string
    {
        if (! is_string($value)) {
            return null;
        }
        $trimmed = trim($value);
        return $trimmed === '' ? null : $trimmed;
    }

    private function normalizePresenceState(?string $value): ?string
    {
        $allowed = ['online', 'stale', 'offline', 'reconnecting'];
        if (! $value) {
            return null;
        }

        return in_array($value, $allowed, true) ? $value : null;
    }

    private function presenceToLifecycleState(string $presenceState): string
    {
        return match ($presenceState) {
            'online' => 'active',
            'stale' => 'degraded',
            'offline' => 'offline',
            'reconnecting' => 'degraded',
            default => 'unknown',
        };
    }

    private function toFloat(mixed $value): ?float
    {
        if ($value === null) {
            return null;
        }
        if (is_numeric($value)) {
            return (float) $value;
        }
        if (is_string($value)) {
            $candidate = str_replace('%', '', trim($value));
            if ($candidate === '') {
                return null;
            }
            if (is_numeric($candidate)) {
                return (float) $candidate;
            }
        }

        return null;
    }
}
