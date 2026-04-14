<?php

namespace App\Http\Controllers\Policy;

use App\Http\Controllers\Controller;
use App\Models\Device;
use App\Models\PolicyProfile;
use App\Services\CommandRegistry\Registry;
use App\Services\PolicyEngine\FastApiPolicyPushService;
use App\Services\PolicyEngine\PolicyEvaluator;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;
use RuntimeException;

class PolicyController extends Controller
{
    private const APP_LOCK_PROFILE_ID = 'app_lock_v1';
    private const APP_LOCK_PROFILE_PREFIX = 'app_lock_device_';

    public function __construct(
        private readonly PolicyEvaluator $policyEvaluator,
        private readonly Registry $registry,
        private readonly FastApiPolicyPushService $policyPushService,
    ) {
    }

    public function evaluate(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'device_id' => ['required', 'string'],
            'device_lifecycle_state' => ['required', 'string'],
            'method' => ['required', 'string'],
            'params' => ['required', 'array'],
            'policy_hash' => ['required', 'string'],
            'timestamp' => ['required', 'string'],
            'user_id' => ['required', 'string'],
            'user_role' => ['required', 'string'],
            'expected_policy_hash' => ['nullable', 'string'],
            'two_factor_verified' => ['nullable', 'boolean'],
        ]);

        if ($validator->fails()) {
            return response()->json([
                'decision' => 'deny',
                'reason' => 'validation_error',
                'errors' => $validator->errors(),
            ], 422);
        }

        $data = $validator->validated();

        $definition = $this->registry->get($data['method']);
        if (! $definition) {
            return response()->json([
                'decision' => 'deny',
                'reason' => 'unknown_command',
            ], 422);
        }

        $device = Device::find($data['device_id']);
        $policy = $this->policyEvaluator->evaluate([
            'user_id' => $data['user_id'],
            'user_role' => $data['user_role'],
            'device_lifecycle_state' => $data['device_lifecycle_state'],
            'policy_hash' => $data['policy_hash'],
            'expected_policy_hash' => $data['expected_policy_hash'] ?? $device?->policy_hash,
            'two_factor_verified' => $data['two_factor_verified'] ?? false,
        ], $definition, $device);

        return response()->json($policy);
    }

    public function validateBundle(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'policy_version' => ['required', 'string'],
            'rules' => ['required', 'array'],
            'signature' => ['required', 'string'],
        ]);

        if ($validator->fails()) {
            return response()->json([
                'status' => 'invalid',
                'errors' => $validator->errors()->all(),
            ], 422);
        }

        $rules = $validator->validated()['rules'];
        $unknownCommands = collect($rules['commands'] ?? [])
            ->reject(fn (array $rule) => $this->registry->get($rule['command'] ?? '') !== null)
            ->values()
            ->all();

        if (! empty($unknownCommands)) {
            return response()->json([
                'status' => 'invalid',
                'errors' => ['unknown_commands' => $unknownCommands],
            ], 422);
        }

        return response()->json([
            'status' => 'valid',
            'errors' => [],
        ]);
    }

    public function appLockShow(): JsonResponse
    {
        $targetDeviceId = $this->normalizeTargetDeviceId(request());
        $profileId = $this->appLockProfileId($targetDeviceId);
        $profile = PolicyProfile::query()
            ->where('profile_id', $profileId)
            ->first();

        if (! $profile && $targetDeviceId !== null) {
            $profile = PolicyProfile::query()
                ->where('profile_id', self::APP_LOCK_PROFILE_ID)
                ->first();
        }

        $rules = is_array($profile?->rules) ? $profile->rules : [];
        $bundle = $this->normalizeAppLockBundle($rules);

        return response()->json([
            'status' => 'ok',
            'scope' => $targetDeviceId === null ? 'global' : 'device',
            'device_id' => $targetDeviceId,
            'profile_id' => $profile?->profile_id ?? $profileId,
            'app_lock' => $bundle,
        ]);
    }

    public function appLockUpsert(Request $request): JsonResponse
    {
        $targetDeviceId = $this->normalizeTargetDeviceId($request);
        $validator = Validator::make($request->all(), [
            'enabled' => ['required', 'boolean'],
            'mode' => ['required', 'in:blocklist'],
            'fail_mode' => ['required', 'in:open'],
            'event_dedupe_sec' => ['nullable', 'integer', 'min:1', 'max:3600'],
            'rules' => ['nullable', 'array'],
            'rules.*.rule_id' => ['required', 'string', 'max:64'],
            'rules.*.match_type' => ['required', 'in:basename,full_path'],
            'rules.*.value' => ['required', 'string', 'max:260'],
            'rules.*.action' => ['nullable', 'in:block'],
            'rules.*.priority' => ['nullable', 'integer', 'min:1', 'max:999999'],
            'rules.*.expires_at' => ['nullable', 'string'],
        ]);

        if ($validator->fails()) {
            return response()->json([
                'status' => 'invalid',
                'errors' => $validator->errors(),
            ], 422);
        }

        $validated = $validator->validated();
        $normalizedRules = collect($validated['rules'] ?? [])
            ->map(function (array $rule): array {
                return [
                    'rule_id' => (string) $rule['rule_id'],
                    'match_type' => (string) $rule['match_type'],
                    'value' => (string) $rule['value'],
                    'action' => 'block',
                    'priority' => (int) ($rule['priority'] ?? 1000),
                    'expires_at' => $rule['expires_at'] ?? null,
                ];
            })
            ->values()
            ->all();

        $bundle = $this->normalizeAppLockBundle([
            'enabled' => (bool) $validated['enabled'],
            'mode' => 'blocklist',
            'fail_mode' => 'open',
            'event_dedupe_sec' => (int) ($validated['event_dedupe_sec'] ?? 30),
            'updated_at' => now()->toIso8601String(),
            'rules' => $normalizedRules,
        ]);

        PolicyProfile::query()->updateOrCreate(
            ['profile_id' => $this->appLockProfileId($targetDeviceId)],
            [
                'description' => 'App lockdown V1 policy bundle',
                'rules' => $bundle,
            ]
        );

        try {
            $pushResponse = $this->policyPushService->pushAppLockPolicy(
                $bundle,
                $targetDeviceId === null ? null : [$targetDeviceId],
            );
        } catch (RuntimeException $e) {
            return response()->json([
                'status' => 'saved_local',
                'push_status' => 'failed',
                'message' => $e->getMessage(),
                'scope' => $targetDeviceId === null ? 'global' : 'device',
                'device_id' => $targetDeviceId,
                'app_lock' => $bundle,
            ], 502);
        }

        return response()->json([
            'status' => 'accepted',
            'push_status' => $pushResponse['status'] ?? 'accepted',
            'scope' => $targetDeviceId === null ? 'global' : 'device',
            'device_id' => $targetDeviceId,
            'app_lock' => $bundle,
        ]);
    }

    public function appLockClear(Request $request): JsonResponse
    {
        $targetDeviceId = $this->normalizeTargetDeviceId($request);
        $bundle = $this->normalizeAppLockBundle([
            'enabled' => false,
            'mode' => 'blocklist',
            'fail_mode' => 'open',
            'event_dedupe_sec' => 30,
            'updated_at' => now()->toIso8601String(),
            'rules' => [],
        ]);

        PolicyProfile::query()->updateOrCreate(
            ['profile_id' => $this->appLockProfileId($targetDeviceId)],
            [
                'description' => 'App lockdown V1 policy bundle',
                'rules' => $bundle,
            ]
        );

        try {
            $pushResponse = $this->policyPushService->pushAppLockPolicy(
                $bundle,
                $targetDeviceId === null ? null : [$targetDeviceId],
            );
        } catch (RuntimeException $e) {
            return response()->json([
                'status' => 'saved_local',
                'push_status' => 'failed',
                'message' => $e->getMessage(),
                'scope' => $targetDeviceId === null ? 'global' : 'device',
                'device_id' => $targetDeviceId,
                'app_lock' => $bundle,
            ], 502);
        }

        return response()->json([
            'status' => 'cleared',
            'push_status' => $pushResponse['status'] ?? 'accepted',
            'scope' => $targetDeviceId === null ? 'global' : 'device',
            'device_id' => $targetDeviceId,
            'app_lock' => $bundle,
        ]);
    }

    private function normalizeTargetDeviceId(Request $request): ?string
    {
        $value = trim((string) $request->query('device_id', ''));
        return $value === '' ? null : $value;
    }

    private function appLockProfileId(?string $targetDeviceId): string
    {
        if ($targetDeviceId === null) {
            return self::APP_LOCK_PROFILE_ID;
        }

        return self::APP_LOCK_PROFILE_PREFIX.$targetDeviceId;
    }

    /**
     * @param  array<string, mixed>  $raw
     * @return array<string, mixed>
     */
    private function normalizeAppLockBundle(array $raw): array
    {
        $normalized = [
            'enabled' => (bool) ($raw['enabled'] ?? false),
            'mode' => 'blocklist',
            'fail_mode' => 'open',
            'policy_version' => (string) config('policy.version'),
            'policy_hash' => (string) config('policy.master_hash'),
            'event_dedupe_sec' => max(1, min(3600, (int) ($raw['event_dedupe_sec'] ?? 30))),
            'updated_at' => (string) ($raw['updated_at'] ?? now()->toIso8601String()),
            'rules' => [],
        ];

        foreach (($raw['rules'] ?? []) as $rule) {
            if (! is_array($rule)) {
                continue;
            }

            $matchType = (string) ($rule['match_type'] ?? '');
            if (! in_array($matchType, ['basename', 'full_path'], true)) {
                continue;
            }

            $value = (string) ($rule['value'] ?? '');
            if ($value === '') {
                continue;
            }

            $normalized['rules'][] = [
                'rule_id' => (string) ($rule['rule_id'] ?? ('rule-'.count($normalized['rules']))),
                'match_type' => $matchType,
                'value' => $value,
                'action' => 'block',
                'priority' => max(1, min(999999, (int) ($rule['priority'] ?? 1000))),
                'expires_at' => $rule['expires_at'] ?? null,
            ];
        }

        return $normalized;
    }
}
