<?php

namespace App\Http\Controllers\Commands;

use App\Http\Controllers\Controller;
use App\Models\AuthToken;
use App\Models\MobileDevice;
use App\Services\Commands\CommandService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class CommandController extends Controller
{
    private const ORIGIN_CONTROL_UI = 'control_ui';
    private const ORIGIN_MOBILE_APP = 'mobile_app';
    private const ORIGIN_API = 'api';

    public function __construct(private readonly CommandService $commandService)
    {
    }

    public function store(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'client_message_id' => ['required', 'string', 'max:190'],
            'device_id' => ['required', 'string', 'max:190'],
            'method' => ['required', 'string', 'max:190'],
            // Commands like lock_screen legitimately have an empty params object.
            'params' => ['present', 'array'],
            'sensitive' => ['required', 'boolean'],
            'two_factor_code' => ['nullable', 'string', 'max:190'],
            'policy_hash' => ['nullable', 'string'],
            'user_id' => ['nullable', 'string'],
            'user_role' => ['nullable', 'string'],
            'attestation_status' => ['nullable', 'string'],
            'last_update_state' => ['nullable', 'string'],
            'clock_skew_seconds' => ['nullable', 'integer'],
        ]);

        if ($validator->fails()) {
            return response()->json([
                'status' => 'rejected',
                'reason' => 'validation_error',
                'errors' => $validator->errors(),
            ], 422);
        }

        $validated = $validator->validated();
        $user = $request->user();
        if ($user) {
            $validated['user_id'] = (string) $user->id;
            $validated['user_role'] = (string) ($user->role ?? 'viewer');
        } else {
            $validated['user_id'] = isset($validated['user_id']) ? (string) $validated['user_id'] : null;
            $validated['user_role'] = (string) ($validated['user_role'] ?? 'viewer');
        }

        $sessionId = $request->attributes->get('jwt_session_id');
        $sessionId = is_string($sessionId) && trim($sessionId) !== '' ? trim($sessionId) : null;

        $originMobileDeviceId = $this->resolveOriginMobileDeviceId($validated['user_id'] ?? null, $sessionId);

        $validated['origin_session_id'] = $sessionId;
        $validated['origin_mobile_device_id'] = $originMobileDeviceId;
        $validated['origin_channel'] = $this->resolveOriginChannel($request, $sessionId, $originMobileDeviceId);

        $result = $this->commandService->enqueue($validated);

        if ($result['status'] !== 'accepted') {
            return response()->json([
                'status' => $result['status'],
                'reason' => $result['reason'] ?? null,
                'policy' => $result['policy'] ?? null,
                'compliance' => $result['compliance'] ?? null,
                'errors' => $result['errors'] ?? null,
            ], ($result['status'] === 'require_2fa' || ($result['reason'] ?? null) === 'invalid_2fa') ? 403 : 422);
        }

        $command = $result['command'];

        return response()->json([
            'command_id' => $command->id,
            'device_id' => $command->device_id,
            'method' => $command->method,
            'params' => $command->params ?? [],
            'queued_at' => $command->queued_at?->toIso8601String(),
            'completed_at' => $command->completed_at?->toIso8601String(),
            'reason' => $command->reason,
            'state' => $command->state,
            'status' => 'accepted',
            'policy' => $result['policy'],
            'compliance' => $result['compliance'],
        ], 201);
    }

    private function resolveOriginChannel(Request $request, ?string $sessionId, ?string $originMobileDeviceId): string
    {
        $headerValue = strtolower(trim((string) $request->header('X-Quoodle-Client-Channel', '')));
        if ($headerValue === self::ORIGIN_CONTROL_UI || $headerValue === self::ORIGIN_MOBILE_APP || $headerValue === self::ORIGIN_API) {
            return $headerValue;
        }

        if ($originMobileDeviceId !== null) {
            return self::ORIGIN_MOBILE_APP;
        }

        if ($sessionId !== null) {
            return self::ORIGIN_CONTROL_UI;
        }

        return self::ORIGIN_API;
    }

    private function resolveOriginMobileDeviceId(?string $userId, ?string $sessionId): ?string
    {
        if ($userId === null || trim($userId) === '' || $sessionId === null || trim($sessionId) === '') {
            return null;
        }

        $authToken = AuthToken::query()
            ->where('session_id', $sessionId)
            ->where('user_id', $userId)
            ->whereNull('revoked_at')
            ->first(['device_fingerprint']);

        $fingerprint = is_string($authToken?->device_fingerprint) ? trim($authToken->device_fingerprint) : '';
        if ($fingerprint === '') {
            return null;
        }

        return MobileDevice::query()
            ->where('user_id', $userId)
            ->where('device_fingerprint', $fingerprint)
            ->value('id');
    }
}
