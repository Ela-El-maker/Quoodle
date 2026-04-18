<?php

namespace App\Services\Compliance;

use App\Models\Alert;
use App\Models\Command;
use App\Models\Device;
use App\Models\DeviceTelemetryLatest;
use App\Models\User;
use Carbon\CarbonImmutable;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Request;
use Illuminate\Support\Collection;

class ComplianceOverviewService
{
    private const FIXED_CHECKS = [
        [
            'id' => 'CC-001',
            'category' => 'Attestation',
            'control' => 'TPM-ATTEST-01',
            'description' => 'All devices must pass TPM attestation on boot',
            'severity' => 'critical',
            'failure_status' => 'non_compliant',
        ],
        [
            'id' => 'CC-002',
            'category' => 'Policy Sync',
            'control' => 'POL-SYNC-01',
            'description' => 'Device policy hash must match fleet policy-2026-04',
            'severity' => 'warning',
            'failure_status' => 'drift',
        ],
        [
            'id' => 'CC-003',
            'category' => 'Kernel Guard',
            'control' => 'KG-DRIVER-01',
            'description' => 'Kernel Guard driver must be active on all managed devices',
            'severity' => 'critical',
            'failure_status' => 'non_compliant',
        ],
        [
            'id' => 'CC-004',
            'category' => 'Agent Version',
            'control' => 'AGENT-VER-01',
            'description' => 'All agents must run version 0.0.1 or higher',
            'severity' => 'info',
            'failure_status' => 'non_compliant',
        ],
        [
            'id' => 'CC-005',
            'category' => 'Encryption',
            'control' => 'ENC-DISK-01',
            'description' => 'Full disk encryption must be enabled on all endpoints',
            'severity' => 'info',
            'failure_status' => 'non_compliant',
        ],
        [
            'id' => 'CC-006',
            'category' => 'Command Auth',
            'control' => 'CMD-AUTH-01',
            'description' => 'All commands must be Ed25519 signed and 2FA verified',
            'severity' => 'info',
            'failure_status' => 'non_compliant',
        ],
        [
            'id' => 'CC-007',
            'category' => 'Heartbeat',
            'control' => 'HB-INTERVAL-01',
            'description' => 'Device heartbeat interval must not exceed 60 seconds',
            'severity' => 'warning',
            'failure_status' => 'drift',
        ],
        [
            'id' => 'CC-008',
            'category' => 'Quarantine',
            'control' => 'QUAR-POLICY-01',
            'description' => 'Quarantined devices must block all non-remediation commands',
            'severity' => 'info',
            'failure_status' => 'non_compliant',
        ],
    ];

    private const QUARANTINE_ALLOWED_METHODS = [
        'ping',
        'get_system_info',
        'list_processes',
        'list_services',
        'list_connections',
        'list_mounts',
        'network_info',
        'get_active_window',
        'list_files',
        'download_file',
        'screenshot',
        'attestation',
        'policy_sync',
    ];

    /**
     * @return array{
     *   last_scan_at: string,
     *   summary: array<string, int>,
     *   checks: array<int, array<string, mixed>>
     * }
     */
    public function overview(Request $request): array
    {
        /** @var User|null $user */
        $user = $request->user();
        if (! $user) {
            return [
                'last_scan_at' => now('UTC')->toIso8601String(),
                'summary' => [
                    'compliant' => 0,
                    'drift' => 0,
                    'non_compliant' => 0,
                    'pending' => count(self::FIXED_CHECKS),
                    'total' => count(self::FIXED_CHECKS),
                    'score' => 0,
                ],
                'checks' => collect(self::FIXED_CHECKS)->map(fn (array $check): array => [
                    'id' => $check['id'],
                    'category' => $check['category'],
                    'control' => $check['control'],
                    'description' => $check['description'],
                    'status' => 'pending',
                    'affected_devices' => 0,
                    'last_checked' => now('UTC')->toIso8601String(),
                    'severity' => $check['severity'],
                ])->all(),
            ];
        }

        $now = CarbonImmutable::now('UTC');
        $lastChecked = $now->toIso8601String();

        $devices = Device::query()
            ->when($user->role !== User::ROLE_ADMIN, fn (Builder $query): Builder => $query->where('user_id', $user->id))
            ->get([
                'device_id',
                'user_id',
                'lifecycle_state',
                'last_seen',
                'agent_version',
                'policy_hash',
                'reported_policy_hash',
                'compliance_status',
            ]);

        $deviceIds = $devices->pluck('device_id')->filter(fn (mixed $id): bool => is_string($id) && trim($id) !== '')->values();

        /** @var Collection<string, DeviceTelemetryLatest> $telemetryLatest */
        $telemetryLatest = DeviceTelemetryLatest::query()
            ->whereIn('device_id', $deviceIds)
            ->get(['device_id', 'metrics', 'policy_hash'])
            ->keyBy('device_id');

        $recentCommands = Command::query()
            ->when(
                $user->role !== User::ROLE_ADMIN,
                fn (Builder $query): Builder => $query->whereHas('device', fn (Builder $deviceQuery): Builder => $deviceQuery->where('user_id', $user->id))
            )
            ->where(function (Builder $query): void {
                $query->whereNotNull('queued_at')->where('queued_at', '>=', now('UTC')->subDays(14))
                    ->orWhere(function (Builder $createdQuery): void {
                        $createdQuery->whereNull('queued_at')->where('created_at', '>=', now('UTC')->subDays(14));
                    });
            })
            ->orderByDesc('queued_at')
            ->orderByDesc('id')
            ->limit(3000)
            ->get([
                'id',
                'device_id',
                'method',
                'state',
                'queued_at',
                'created_at',
                'sensitive',
                'request_sig',
                'envelope_sig',
            ]);

        $alerts = Alert::query()
            ->whereIn('device_id', $deviceIds)
            ->where('timestamp', '>=', now('UTC')->subDays(30))
            ->orderByDesc('timestamp')
            ->limit(3000)
            ->get(['device_id', 'severity', 'category', 'message', 'acknowledged']);

        $attestationAlertDevices = $alerts->filter(function (Alert $alert): bool {
            $category = strtolower((string) $alert->category);
            $message = strtolower((string) $alert->message);
            return str_contains($category, 'attestation') || str_contains($message, 'attestation');
        })->pluck('device_id')->filter()->unique()->values();

        $kernelAlertDevices = $alerts->filter(function (Alert $alert): bool {
            $message = strtolower((string) $alert->message);
            return str_contains($message, 'kernel guard') || str_contains($message, 'kernel');
        })->pluck('device_id')->filter()->unique()->values();

        $encryptionAlertDevices = $alerts->filter(function (Alert $alert): bool {
            $category = strtolower((string) $alert->category);
            $message = strtolower((string) $alert->message);
            return str_contains($category, 'encryption')
                || str_contains($message, 'encryption')
                || str_contains($message, 'bitlocker')
                || str_contains($message, 'disk');
        })->pluck('device_id')->filter()->unique()->values();

        $nonCompliantDevices = $devices
            ->filter(function (Device $device): bool {
                $status = strtolower((string) $device->compliance_status);
                return in_array($status, ['non_compliant', 'quarantined'], true);
            })
            ->pluck('device_id')
            ->values();

        $policySignalCount = 0;
        $policyMismatchDevices = collect();
        foreach ($devices as $device) {
            $expectedHash = trim((string) ($device->policy_hash ?? ''));
            $reportedHash = trim((string) ($telemetryLatest[$device->device_id]->policy_hash ?? ''));
            if ($reportedHash === '') {
                $reportedHash = trim((string) ($device->reported_policy_hash ?? ''));
            }
            if ($expectedHash === '' || $reportedHash === '') {
                continue;
            }
            $policySignalCount += 1;
            if (! hash_equals($expectedHash, $reportedHash)) {
                $policyMismatchDevices->push($device->device_id);
            }
        }
        $policyMismatchDevices = $policyMismatchDevices->unique()->values();

        $kernelSignalCount = 0;
        $kernelOffDevices = collect();
        foreach ($deviceIds as $deviceId) {
            $metrics = is_array($telemetryLatest[$deviceId]->metrics ?? null) ? $telemetryLatest[$deviceId]->metrics : [];
            $kernel = $this->firstBooleanMetric($metrics, ['kernel_guard', 'kernel_mode']);
            if ($kernel === null) {
                continue;
            }
            $kernelSignalCount += 1;
            if ($kernel === false) {
                $kernelOffDevices->push($deviceId);
            }
        }
        $kernelOffDevices = $kernelOffDevices->concat($kernelAlertDevices)->unique()->values();

        $agentSignalCount = 0;
        $oldAgentDevices = collect();
        foreach ($devices as $device) {
            $version = trim((string) ($device->agent_version ?? ''));
            if ($version === '') {
                continue;
            }
            $agentSignalCount += 1;
            if (version_compare($version, '0.0.1', '<')) {
                $oldAgentDevices->push($device->device_id);
            }
        }
        $oldAgentDevices = $oldAgentDevices->unique()->values();

        $encryptionSignalCount = 0;
        $encryptionOffDevices = collect();
        foreach ($deviceIds as $deviceId) {
            $metrics = is_array($telemetryLatest[$deviceId]->metrics ?? null) ? $telemetryLatest[$deviceId]->metrics : [];
            $encryptionEnabled = $this->firstBooleanMetric($metrics, ['disk_encrypted', 'full_disk_encryption', 'encryption_enabled']);
            if ($encryptionEnabled === null) {
                continue;
            }
            $encryptionSignalCount += 1;
            if ($encryptionEnabled === false) {
                $encryptionOffDevices->push($deviceId);
            }
        }
        $encryptionOffDevices = $encryptionOffDevices->concat($encryptionAlertDevices)->unique()->values();

        $authSignalCommands = $recentCommands->filter(function (Command $command): bool {
            $state = strtolower((string) $command->state);
            return ! in_array($state, ['queued'], true);
        })->values();
        $unsignedCommandDevices = $authSignalCommands
            ->filter(function (Command $command): bool {
                $requestSig = trim((string) ($command->request_sig ?? ''));
                $envelopeSig = trim((string) ($command->envelope_sig ?? ''));
                return $requestSig === '' || $envelopeSig === '';
            })
            ->pluck('device_id')
            ->filter()
            ->unique()
            ->values();

        $heartbeatTargetDevices = $devices->filter(function (Device $device): bool {
            $state = strtolower((string) $device->lifecycle_state);
            return in_array($state, ['online', 'active', 'degraded'], true);
        })->values();
        $heartbeatSignalCount = $heartbeatTargetDevices->count();
        $heartbeatDriftDevices = $heartbeatTargetDevices->filter(function (Device $device): bool {
            if (! $device->last_seen) {
                return true;
            }
            return $device->last_seen->diffInSeconds(now('UTC')) > 60;
        })->pluck('device_id')->values();

        $quarantinedDevices = $devices->filter(function (Device $device): bool {
            $lifecycle = strtolower((string) $device->lifecycle_state);
            $compliance = strtolower((string) $device->compliance_status);
            return $lifecycle === 'quarantined' || $compliance === 'quarantined';
        })->pluck('device_id')->filter()->unique()->values();

        $quarantineViolations = $recentCommands
            ->filter(fn (Command $command): bool => in_array((string) $command->device_id, $quarantinedDevices->all(), true))
            ->filter(function (Command $command): bool {
                $state = strtolower((string) $command->state);
                if (in_array($state, ['failed', 'expired', 'rejected'], true)) {
                    return false;
                }
                $method = strtolower(trim((string) $command->method));
                return ! in_array($method, self::QUARANTINE_ALLOWED_METHODS, true);
            })
            ->pluck('device_id')
            ->filter()
            ->unique()
            ->values();

        $checks = collect(self::FIXED_CHECKS)->map(function (array $definition) use (
            $lastChecked,
            $deviceIds,
            $attestationAlertDevices,
            $nonCompliantDevices,
            $policySignalCount,
            $policyMismatchDevices,
            $kernelSignalCount,
            $kernelOffDevices,
            $agentSignalCount,
            $oldAgentDevices,
            $encryptionSignalCount,
            $encryptionOffDevices,
            $authSignalCommands,
            $unsignedCommandDevices,
            $heartbeatSignalCount,
            $heartbeatDriftDevices,
            $quarantineViolations
        ): array {
            $affected = collect();
            $hasSignal = false;
            $status = 'pending';

            switch ($definition['id']) {
                case 'CC-001':
                    $hasSignal = $deviceIds->isNotEmpty();
                    $affected = $attestationAlertDevices->isNotEmpty() ? $attestationAlertDevices : $nonCompliantDevices;
                    break;
                case 'CC-002':
                    $hasSignal = $policySignalCount > 0;
                    $affected = $policyMismatchDevices;
                    break;
                case 'CC-003':
                    $hasSignal = $kernelSignalCount > 0 || $kernelOffDevices->isNotEmpty();
                    $affected = $kernelOffDevices;
                    break;
                case 'CC-004':
                    $hasSignal = $agentSignalCount > 0;
                    $affected = $oldAgentDevices;
                    break;
                case 'CC-005':
                    $hasSignal = $encryptionSignalCount > 0 || $encryptionOffDevices->isNotEmpty();
                    $affected = $encryptionOffDevices;
                    break;
                case 'CC-006':
                    $hasSignal = $authSignalCommands->isNotEmpty();
                    $affected = $unsignedCommandDevices;
                    break;
                case 'CC-007':
                    $hasSignal = $heartbeatSignalCount > 0;
                    $affected = $heartbeatDriftDevices;
                    break;
                case 'CC-008':
                    $hasSignal = true;
                    $affected = $quarantineViolations;
                    break;
            }

            if ($hasSignal) {
                $status = $affected->isNotEmpty()
                    ? (string) $definition['failure_status']
                    : 'compliant';
            }

            return [
                'id' => $definition['id'],
                'category' => $definition['category'],
                'control' => $definition['control'],
                'description' => $definition['description'],
                'status' => $status,
                'affected_devices' => $affected->unique()->count(),
                'last_checked' => $lastChecked,
                'severity' => $definition['severity'],
            ];
        })->values();

        $summary = [
            'compliant' => $checks->where('status', 'compliant')->count(),
            'drift' => $checks->where('status', 'drift')->count(),
            'non_compliant' => $checks->where('status', 'non_compliant')->count(),
            'pending' => $checks->where('status', 'pending')->count(),
            'total' => $checks->count(),
            'score' => $checks->count() > 0
                ? (int) round(($checks->where('status', 'compliant')->count() / $checks->count()) * 100)
                : 0,
        ];

        return [
            'last_scan_at' => $lastChecked,
            'summary' => $summary,
            'checks' => $checks->all(),
        ];
    }

    /**
     * @param  array<string, mixed>  $metrics
     */
    private function firstBooleanMetric(array $metrics, array $keys): ?bool
    {
        foreach ($keys as $key) {
            if (! array_key_exists($key, $metrics)) {
                continue;
            }
            if (is_bool($metrics[$key])) {
                return $metrics[$key];
            }
            if (is_numeric($metrics[$key])) {
                return ((int) $metrics[$key]) !== 0;
            }
            if (is_string($metrics[$key])) {
                $value = strtolower(trim($metrics[$key]));
                if (in_array($value, ['1', 'true', 'yes', 'enabled'], true)) {
                    return true;
                }
                if (in_array($value, ['0', 'false', 'no', 'disabled'], true)) {
                    return false;
                }
            }
        }

        return null;
    }
}

