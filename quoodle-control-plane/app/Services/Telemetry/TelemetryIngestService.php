<?php

namespace App\Services\Telemetry;

use App\Models\Device;
use App\Models\TelemetrySnapshot;

class TelemetryIngestService
{
    public function ingest(string $deviceId, array $payload): array
    {
        $rollup = $payload['rollup'] ?? [];
        $snapshot = TelemetrySnapshot::create([
            'device_id' => $deviceId,
            'timestamp' => $payload['timestamp'] ?? now(),
            'metrics' => [
                'cpu' => $rollup['avg_cpu'] ?? null,
                'ram' => $rollup['avg_ram'] ?? null,
                'disk_usage' => $rollup['avg_disk'] ?? null,
                'network_tx' => $rollup['avg_tx'] ?? null,
                'network_rx' => $rollup['avg_rx'] ?? null,
                'risk_score' => $rollup['risk_score_avg'] ?? null,
                'policy_hash' => $rollup['policy_hash'] ?? null,
            ],
        ]);

        Device::where('device_id', $deviceId)->update([
            'last_seen' => now(),
            'risk_score' => $snapshot->metrics['risk_score'] ?? null,
            'reported_policy_hash' => $snapshot->metrics['policy_hash'] ?? null,
        ]);

        return [
            'status' => 'ingested',
            'snapshot_id' => $snapshot->id ?? null,
            'timestamp' => $snapshot->timestamp?->toIso8601String(),
        ];
    }
}
