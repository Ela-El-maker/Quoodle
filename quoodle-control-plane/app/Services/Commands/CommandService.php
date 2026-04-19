<?php

namespace App\Services\Commands;

use App\Jobs\DispatchCommandToFastApi;
use App\Jobs\ExpireCommandJob;
use App\Models\Command;
use App\Models\Device;
use App\Models\User;
use App\Services\CommandRegistry\Registry;
use App\Services\Compliance\ComplianceChecker;
use App\Services\Integrations\Webhooks\OutboundWebhookPublisher;
use App\Services\PolicyEngine\PolicyEvaluator;
use App\Services\Security\StateVerifier;
use App\Services\Security\TOTPService;
use Illuminate\Support\Str;

class CommandService
{
    /**
     * Methods that are allowed to execute even when compliance status is non_compliant.
     * Keep this list intentionally narrow.
     *
     * @var array<int, string>
     */
    private const COMPLIANCE_BYPASS_METHODS = [
        'screenshot',
        // Observability slices (read-only collectors).
        'list_processes',
        'list_services',
        'list_connections',
        'list_mounts',
        // Phase 2 observability slice (read-only collectors).
        'network_info',
        'get_active_window',
        // Filesystem read-only slice.
        'list_files',
        'download_file',
    ];

    public function __construct(
        private readonly Registry $registry,
        private readonly RuntimeCapabilities $runtimeCapabilities,
        private readonly PolicyEvaluator $policyEvaluator,
        private readonly ComplianceChecker $complianceChecker,
        private readonly FastAPIDispatcher $dispatcher,
        private readonly TOTPService $totp,
        private readonly StateVerifier $stateVerifier,
        private readonly OutboundWebhookPublisher $outboundWebhookPublisher,
    ) {
    }

    public function enqueue(array $payload): array
    {
        $method = isset($payload['method']) ? (string) $payload['method'] : '';
        $ttlSeconds = (int) config('security.command_ttl_seconds', 300);
        $expiryGrace = (int) config('security.command_expiry_grace_seconds', 120);
        $device = Device::find($payload['device_id']);
        if (! $device) {
            return ['status' => 'rejected', 'reason' => 'device_not_found'];
        }

        $existing = Command::where('client_message_id', $payload['client_message_id'])
            ->where('device_id', $payload['device_id'])
            ->first();
        if ($existing) {
            return [
                'status' => 'accepted',
                'state' => $existing->state,
                'policy' => null,
                'compliance' => null,
                'command' => $existing,
            ];
        }

        $definition = $this->registry->get($method);
        if (! $definition) {
            return ['status' => 'rejected', 'reason' => 'unknown_command'];
        }

        if (! $this->runtimeCapabilities->isRuntimeSupported($method)) {
            return ['status' => 'rejected', 'reason' => 'not_supported_runtime'];
        }

        // Defensive normalization for list_files so stale clients cannot trigger
        // repeated invalid_params rejections (e.g., limit > max bound).
        if ($method === 'list_files') {
            $params = is_array($payload['params'] ?? null) ? $payload['params'] : [];

            if (array_key_exists('limit', $params)) {
                $limit = is_numeric($params['limit']) ? (int) $params['limit'] : null;
                if ($limit !== null) {
                    $params['limit'] = max(1, min($limit, 1000));
                }
            }

            if (array_key_exists('max_depth', $params)) {
                $depth = is_numeric($params['max_depth']) ? (int) $params['max_depth'] : null;
                if ($depth !== null) {
                    $params['max_depth'] = max(1, min($depth, 16));
                }
            }

            $payload['params'] = $params;
        }

        $validation = $definition->validate($payload['params'] ?? []);
        if (! $validation['valid']) {
            return [
                'status' => 'rejected',
                'reason' => 'invalid_params',
                'errors' => $validation['errors'],
            ];
        }

        $compliance = $this->complianceChecker->evaluateDevice($device, [
            'policy_hash' => $payload['policy_hash'] ?? null,
            'expected_policy_hash' => $device->policy_hash,
            'attestation_status' => $payload['attestation_status'] ?? 'unknown',
            'last_update_state' => $payload['last_update_state'] ?? null,
            'clock_skew_seconds' => $payload['clock_skew_seconds'] ?? 0,
        ]);

        if (
            $compliance['status'] === 'non_compliant'
            && $definition->riskLevel !== 'low'
            && ! in_array($method, self::COMPLIANCE_BYPASS_METHODS, true)
        ) {
            return ['status' => 'rejected', 'reason' => 'compliance_failed', 'compliance' => $compliance];
        }

        $twoFactorVerified = false;
        $twoFactorCode = $payload['two_factor_code'] ?? null;
        $userId = $payload['user_id'] ?? null;
        if (is_string($twoFactorCode) && $twoFactorCode !== '' && is_string($userId) && $userId !== '') {
            $user = User::find($userId);
            if ($user && $user->two_factor_enabled && ! empty($user->two_factor_secret)) {
                $twoFactorVerified = $this->totp->verify($user->two_factor_secret, $twoFactorCode);
            }
        }

        $policy = $this->policyEvaluator->evaluate([
            'user_id' => $payload['user_id'] ?? 'unknown',
            'user_role' => $payload['user_role'] ?? 'user',
            'device_lifecycle_state' => $device->lifecycle_state,
            'policy_hash' => $payload['policy_hash'] ?? null,
            'expected_policy_hash' => $device->policy_hash,
            'two_factor_verified' => $twoFactorVerified,
        ], $definition, $device);

        if ($policy['decision'] === 'deny') {
            return ['status' => 'rejected', 'reason' => $policy['reason'], 'policy' => $policy];
        }

        if ($policy['decision'] === 'require_2fa' && empty($payload['two_factor_code'])) {
            return ['status' => 'require_2fa', 'reason' => '2fa_required', 'policy' => $policy];
        }

        if ($policy['decision'] === 'require_2fa' && ! empty($payload['two_factor_code']) && ! $twoFactorVerified) {
            return ['status' => 'rejected', 'reason' => 'invalid_2fa', 'policy' => $policy];
        }

        $queuedAt = now();
        $command = Command::create([
            'client_message_id' => $payload['client_message_id'],
            'device_id' => $payload['device_id'],
            'user_id' => $payload['user_id'] ?? null,
            'method' => $payload['method'],
            'params' => $payload['params'] ?? [],
            'sensitive' => $payload['sensitive'] ?? false,
            'trace_id' => (string) Str::uuid(),
            'queued_at' => $queuedAt,
            'state' => 'queued',
            'status' => 'accepted',
            'execution_state' => 'queued',
            'ttl_seconds' => $ttlSeconds,
            'expires_at' => $queuedAt->copy()->addSeconds($ttlSeconds),
        ]);
        $this->outboundWebhookPublisher->publish('command.queued', [
            'command_id' => $command->id,
            'device_id' => $command->device_id,
            'method' => $command->method,
            'actor_user_id' => $command->user_id,
            'queued_at' => $command->queued_at?->toIso8601String(),
            'trace_id' => $command->trace_id,
        ]);

        // Ground-truth loop: after sensitive commands, require telemetry to confirm policy sync.
        if (! empty($payload['sensitive'])) {
            $delay = (int) config('security.state_verify_delay_seconds', 10);
            $this->stateVerifier->registerPolicyHashCheck($command, $device, $delay);
        }

        // Async dispatch to avoid blocking the mobile/UI call path.
        DispatchCommandToFastApi::dispatch($command->id, $policy, $compliance);
        ExpireCommandJob::dispatch($command->id)->delay($queuedAt->copy()->addSeconds($ttlSeconds + $expiryGrace));

        $state = 'queued';

        return [
            'status' => 'accepted',
            'state' => $state,
            'policy' => $policy,
            'compliance' => $compliance,
            'command' => $command,
        ];
    }
}
