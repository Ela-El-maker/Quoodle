<?php

namespace App\Services\Telemetry;

class TelemetryIngestService
{
    public function ingest(array $metrics): array
    {
        return [
            'status' => 'ingested',
            'metrics' => $metrics,
        ];
    }
}
