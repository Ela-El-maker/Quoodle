<?php

use Illuminate\Foundation\Inspiring;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Schedule;
use App\Models\Command;
use App\Models\Device;
use App\Models\DeviceTelemetryLatest;
use App\Models\TelemetryEvent;
use App\Models\TelemetryIngestError;

Artisan::command('inspire', function () {
    $this->comment(Inspiring::quote());
})->purpose('Display an inspiring quote');

Artisan::command('jwt:generate-keys {--force : Overwrite existing keys}', function () {
    $privPath = (string) config('jwt.private_key_path');
    $pubPath = (string) config('jwt.public_key_path');

    if (! function_exists('openssl_pkey_new')) {
        $this->error('OpenSSL extension not available in PHP.');
        return 1;
    }

    $force = (bool) $this->option('force');
    if (! $force && (file_exists($privPath) || file_exists($pubPath))) {
        $this->error('JWT key(s) already exist. Use --force to overwrite.');
        $this->line("private: {$privPath}");
        $this->line("public : {$pubPath}");
        return 1;
    }

    $dir = dirname($privPath);
    if (! is_dir($dir)) {
        @mkdir($dir, 0775, true);
    }

    $this->info('Generating RSA keypair for PS256...');
    $res = openssl_pkey_new([
        'private_key_type' => OPENSSL_KEYTYPE_RSA,
        'private_key_bits' => 2048,
    ]);
    if ($res === false) {
        $this->error('openssl_pkey_new failed.');
        return 1;
    }

    $privPem = '';
    if (! openssl_pkey_export($res, $privPem)) {
        $this->error('openssl_pkey_export failed.');
        return 1;
    }

    $details = openssl_pkey_get_details($res);
    if (! is_array($details) || empty($details['key'])) {
        $this->error('openssl_pkey_get_details failed.');
        return 1;
    }
    $pubPem = (string) $details['key'];

    file_put_contents($privPath, $privPem);
    file_put_contents($pubPath, $pubPem);

    $this->info('JWT keys written:');
    $this->line("private: {$privPath}");
    $this->line("public : {$pubPath}");
    return 0;
})->purpose('Generate JWT signing keys for API tokens');

Artisan::command('telemetry:reconcile-device-os-build {--dry-run : Preview changes only}', function () {
    $dryRun = (bool) $this->option('dry-run');

    $rows = DeviceTelemetryLatest::query()->get(['device_id', 'metrics']);
    $examined = 0;
    $updated = 0;

    foreach ($rows as $row) {
        $examined++;
        $metrics = is_array($row->metrics) ? $row->metrics : [];
        $osBuild = isset($metrics['os_build']) && is_string($metrics['os_build']) ? trim($metrics['os_build']) : '';
        if ($osBuild === '') {
            continue;
        }

        $device = Device::query()->where('device_id', $row->device_id)->first();
        if (! $device) {
            continue;
        }

        $current = is_string($device->os_build) ? trim($device->os_build) : '';
        if ($current === $osBuild) {
            continue;
        }

        $updated++;
        $this->line(sprintf(
            '%s: %s -> %s',
            $row->device_id,
            $current === '' ? '(empty)' : $current,
            $osBuild
        ));

        if (! $dryRun) {
            $device->update(['os_build' => $osBuild]);
        }
    }

    $this->info(sprintf(
        'Reconciliation complete. examined=%d updated=%d mode=%s',
        $examined,
        $updated,
        $dryRun ? 'dry-run' : 'apply'
    ));

    return 0;
})->purpose('Reconcile devices.os_build from telemetry latest metrics.os_build');

Artisan::command('commands:reconcile-stale {--dry-run : Preview changes only} {--limit=500 : Max rows to reconcile per run} {--grace-seconds=120 : Grace period after expires_at}', function () {
    $dryRun = (bool) $this->option('dry-run');
    $limit = max(1, (int) $this->option('limit'));
    $graceSeconds = max(0, (int) $this->option('grace-seconds'));
    $now = now();

    $candidates = Command::query()
        ->whereIn('state', ['queued', 'dispatched', 'sent', 'ack_received'])
        ->where(function ($query) use ($now, $graceSeconds): void {
            $query->where(function ($q) use ($now, $graceSeconds): void {
                $q->whereNotNull('expires_at')
                    ->where('expires_at', '<=', $now->copy()->subSeconds($graceSeconds));
            })->orWhere(function ($q) use ($now): void {
                $q->whereNull('expires_at')
                    ->whereNotNull('queued_at')
                    ->where('queued_at', '<=', $now->copy()->subMinutes(30));
            });
        })
        ->orderBy('queued_at')
        ->limit($limit)
        ->get();

    $expired = 0;
    foreach ($candidates as $command) {
        $reason = $command->state === 'queued' ? 'dispatch_timeout' : 'execution_timeout';
        $expired++;
        $this->line(sprintf(
            '%s %s -> expired (%s)',
            $command->id,
            $command->state,
            $reason
        ));

        if (! $dryRun) {
            $command->update([
                'state' => 'expired',
                'execution_state' => 'expired',
                'reason' => $reason,
                'completed_at' => $now,
            ]);
        }
    }

    if (! $dryRun && $expired > 0) {
        Cache::add('commands:stale_reconciled', 0, now()->addDay());
        Cache::increment('commands:stale_reconciled', $expired);
    }

    $this->info(sprintf(
        'Stale reconciliation complete. reconciled=%d mode=%s',
        $expired,
        $dryRun ? 'dry-run' : 'apply'
    ));

    return 0;
})->purpose('Auto-expire stale queued/dispatched/ack_received commands with deterministic reasons');

Artisan::command('pipeline:readiness-report {--json : Output JSON summary}', function () {
    $gatewayHealthCandidates = [];
    $configuredHealthUrl = config('services.gateway.health_url') ?? env('GATEWAY_HEALTH_URL');
    if (is_string($configuredHealthUrl) && trim($configuredHealthUrl) !== '') {
        $gatewayHealthCandidates[] = rtrim(trim($configuredHealthUrl), '/');
    }

    $fastapiBase = (string) (config('services.fastapi.base_url') ?? env('FASTAPI_BASE_URL') ?? '');
    if (trim($fastapiBase) !== '') {
        $trimmedBase = rtrim(trim($fastapiBase), '/');
        $gatewayHealthCandidates[] = $trimmedBase.'/health';
        $gatewayHealthCandidates[] = preg_replace('#/api/v1$#', '', $trimmedBase).'/health';
    }

    $gatewayHealthCandidates[] = 'http://gateway:8000/health';
    $gatewayHealthCandidates[] = 'http://gateway:8000/api/v1/health';
    $gatewayHealthCandidates = array_values(array_unique(array_filter($gatewayHealthCandidates, fn ($url) => is_string($url) && trim($url) !== '')));

    $gatewayHealth = null;
    $gatewayHealthUrl = $gatewayHealthCandidates[0] ?? '';
    foreach ($gatewayHealthCandidates as $candidate) {
        try {
            $response = Http::timeout(3)->get($candidate);
            if ($response->ok()) {
                $gatewayHealth = $response->json();
                $gatewayHealthUrl = $candidate;
                break;
            }
        } catch (\Throwable $e) {
            // try next candidate
        }
    }

    $oneHourAgo = now()->subHour();
    $recentErrors = TelemetryIngestError::query()
        ->where('timestamp', '>=', $oneHourAgo)
        ->selectRaw('reason, COUNT(*) as total')
        ->groupBy('reason')
        ->pluck('total', 'reason')
        ->toArray();

    $staleCommands = Command::query()
        ->whereIn('state', ['queued', 'dispatched', 'sent', 'ack_received'])
        ->count();

    $recentKernelEvents = TelemetryEvent::query()
        ->where('telemetry_scope', 'kernel_event')
        ->where('timestamp', '>=', $oneHourAgo)
        ->count();

    $gatewaySoftDrops = (int) data_get($gatewayHealth, 'ws_telemetry_counters.seq_replay_soft_drop', 0);
    $duplicatePrevented = (int) Cache::get('telemetry:ingest:duplicate_prevented', 0);
    $rollupConflictsHandled = (int) Cache::get('telemetry:rollup:upsert_conflict_handled', 0);
    $staleReconciled = (int) Cache::get('commands:stale_reconciled', 0);
    $numericOverflowErrors = (int) ($recentErrors['numeric_overflow'] ?? 0);
    $rollupConflictErrors = (int) ($recentErrors['rollup_conflict'] ?? 0);

    $subsystems = [
        'gateway_replay' => [
            'pass' => is_array($gatewayHealth),
            'detail' => [
                'health_url' => $gatewayHealthUrl,
                'seq_replay_soft_drop' => $gatewaySoftDrops,
                'kernel_soft_drop' => (int) data_get($gatewayHealth, 'ws_telemetry_counters.seq_replay_soft_drop_kernel_event', 0),
            ],
        ],
        'telemetry_ingest' => [
            'pass' => $numericOverflowErrors === 0 && $rollupConflictErrors === 0,
            'detail' => [
                'recent_errors' => $recentErrors,
                'duplicate_ingest_prevented' => $duplicatePrevented,
                'rollup_conflicts_handled' => $rollupConflictsHandled,
            ],
        ],
        'command_lifecycle' => [
            'pass' => $staleCommands === 0,
            'detail' => [
                'stale_non_terminal' => $staleCommands,
                'stale_reconciled' => $staleReconciled,
            ],
        ],
        'kernel_pipeline' => [
            'pass' => $recentKernelEvents > 0 || $staleCommands === 0,
            'detail' => [
                'kernel_events_last_hour' => $recentKernelEvents,
            ],
        ],
    ];

    $overallPass = collect($subsystems)->every(fn (array $entry): bool => (bool) $entry['pass']);
    $report = [
        'overall_pass' => $overallPass,
        'generated_at' => now()->toIso8601String(),
        'subsystems' => $subsystems,
    ];

    if ((bool) $this->option('json')) {
        $this->line(json_encode($report, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
    } else {
        $this->info('Opcode Rollout Readiness');
        foreach ($subsystems as $name => $entry) {
            $this->line(sprintf('%s: %s', $name, $entry['pass'] ? 'PASS' : 'FAIL'));
        }
        $this->line('');
        $this->line(json_encode($report, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES));
    }

    return $overallPass ? 0 : 1;
})->purpose('Readiness gate report for kernel opcode rollout');

Schedule::command('commands:reconcile-stale --limit=200')
    ->everyMinute()
    ->withoutOverlapping();
