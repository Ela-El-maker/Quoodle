<?php

namespace App\Http\Controllers\Devices;

use App\Http\Controllers\Controller;
use App\Models\AuthToken;
use App\Models\Device;
use App\Models\DeviceLink;
use App\Models\User;
use App\Services\Devices\FastApiDeviceKeySync;
use App\Services\Devices\FastApiDevicePairedWebhook;
use App\Services\JWT\JWTSigner;
use App\Services\Mobile\MobileDeviceTracker;
use Firebase\JWT\JWT;
use Firebase\JWT\Key;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Auth;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;

class PairingController extends Controller
{
    private const CACHE_PREFIX = 'pair_session_';
    private const CODE_CACHE_PREFIX = 'pair_code_';
    private const PAIR_CODE_LENGTH = 6;

    public function __construct(
        private readonly JWTSigner $jwtSigner,
        private readonly FastApiDeviceKeySync $keySync,
        private readonly FastApiDevicePairedWebhook $pairedWebhook,
        private readonly MobileDeviceTracker $mobileTracker,
    ) {
    }

    public function init(Request $request): JsonResponse
    {
        $user = Auth::user();
        if (! $user) {
            return response()->json(['status' => 'invalid_session'], 401);
        }

        $validator = Validator::make($request->all(), [
            'device_label' => ['nullable', 'string', 'max:190'],
        ]);

        if ($validator->fails()) {
            return response()->json(['message' => 'validation_error', 'errors' => $validator->errors()], 422);
        }

        $pairSessionId = Str::uuid()->toString();
        $pairCode = $this->generateUniquePairCode();
        $expiresAt = now()->addMinutes(10);
        $session = [
            'pair_session_id' => $pairSessionId,
            'pair_code' => $pairCode,
            'device_label' => $validator->validated()['device_label'] ?? null,
            'user_id' => (string) $user->id,
            'status' => 'pending_agent',
            'pair_token' => null,
            'device_id' => null,
            'device_name' => null,
            'detected_at' => null,
            'expires_at' => $expiresAt->toIso8601String(),
        ];

        Cache::put(self::CACHE_PREFIX.$pairSessionId, $session, $expiresAt);
        Cache::put(self::CODE_CACHE_PREFIX.$pairCode, $pairSessionId, $expiresAt);

        return response()->json([
            'pair_session_id' => $pairSessionId,
            'pair_code' => $pairCode,
            'expires_at' => $expiresAt->toIso8601String(),
            'expires_in_seconds' => max(0, now()->diffInSeconds($expiresAt, false)),
            'qr_metadata' => [
                'info' => 'Scan with Windows Agent pairing QR',
            ],
        ]);
    }

    public function request(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'device_name' => ['required', 'string', 'max:190'],
            'hwid' => ['required', 'string', 'max:190'],
            'pubkey' => ['required', 'string', 'max:2048'],
            'pair_code' => ['nullable', 'digits:6'],
            'pair_session_id' => ['nullable', 'string', 'max:64'],
            'identity_version' => ['nullable', 'string', 'max:32'],
            'identity_components' => ['nullable', 'array'],
            'identity_components.mb_uuid' => ['nullable', 'string', 'max:128'],
            'identity_components.cpu_id' => ['nullable', 'string', 'max:128'],
            'identity_components.disk_serial' => ['nullable', 'string', 'max:128'],
            'identity_components.primary_mac' => ['nullable', 'string', 'max:128'],
            'machine_secret_hash' => ['nullable', 'string', 'max:128'],
        ]);

        if ($validator->fails()) {
            return response()->json(['status' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $data = $validator->validated();
        $normalizedPubkey = $this->normalizePubkey((string) $data['pubkey']);
        $identityVersion = isset($data['identity_version']) ? trim((string) $data['identity_version']) : null;
        $identityComponents = $this->normalizeIdentityComponents($data['identity_components'] ?? null);
        $machineSecretHash = isset($data['machine_secret_hash']) ? trim((string) $data['machine_secret_hash']) : null;
        $policyHash = (string) config('policy.master_hash');
        if ($policyHash === '') {
            return response()->json(['status' => 'invalid', 'reason' => 'policy_hash_not_configured'], 500);
        }

        $device = Device::where('hwid', $data['hwid'])->first();
        if (! $device && $identityVersion && ! empty($identityComponents)) {
            $fuzzyMatch = $this->findFuzzyIdentityMatch($identityVersion, $identityComponents);
            if (($fuzzyMatch['status'] ?? null) === 'ambiguous') {
                return response()->json(['status' => 'conflict', 'reason' => 'identity_match_ambiguous'], 409);
            }
            if (($fuzzyMatch['status'] ?? null) === 'matched') {
                $device = $fuzzyMatch['device'] ?? null;
            }
        }

        if ($device && ! empty($device->user_id)) {
            if (! empty($device->ed25519_pubkey_b64) && $this->pubkeysMatch((string) $device->ed25519_pubkey_b64, $normalizedPubkey)) {
                $this->updateIdentityMetadata($device, (string) $data['hwid'], $identityVersion, $identityComponents, $machineSecretHash);
                $pairToken = $this->jwtSigner->issueForDevice(
                    $device->device_id,
                    [
                        'scope' => 'pair_token',
                        'device_name' => $device->device_name,
                        'ed25519_pubkey_b64' => $normalizedPubkey,
                        'hwid' => $device->hwid,
                    ],
                    (int) config('jwt.pair_token_ttl', 300),
                );

                if ($errorResponse = $this->attachPairRequestToSession($data, $device, $pairToken)) {
                    return $errorResponse;
                }

                return response()->json([
                    'pair_token' => $pairToken,
                    'expires_at' => now()->addSeconds((int) config('jwt.pair_token_ttl', 300))->toIso8601String(),
                    'device_id' => $device->device_id,
                ]);
            }

            if (filter_var(env('ALLOW_DEVICE_REPAIR_WITH_HWID', false), FILTER_VALIDATE_BOOL)) {
                $device->update([
                    'device_name' => $data['device_name'],
                    'ed25519_pubkey_b64' => $normalizedPubkey,
                ]);
                $this->updateIdentityMetadata($device, (string) $data['hwid'], $identityVersion, $identityComponents, $machineSecretHash);
                $pairToken = $this->jwtSigner->issueForDevice(
                    $device->device_id,
                    [
                        'scope' => 'pair_token',
                        'device_name' => $device->device_name,
                        'ed25519_pubkey_b64' => $device->ed25519_pubkey_b64,
                        'hwid' => $device->hwid,
                    ],
                    (int) config('jwt.pair_token_ttl', 300),
                );

                if ($errorResponse = $this->attachPairRequestToSession($data, $device, $pairToken)) {
                    return $errorResponse;
                }

                return response()->json([
                    'pair_token' => $pairToken,
                    'expires_at' => now()->addSeconds((int) config('jwt.pair_token_ttl', 300))->toIso8601String(),
                    'device_id' => $device->device_id,
                ]);
            }

            return response()->json(['status' => 'conflict', 'reason' => 'already_claimed'], 409);
        }

        if (! $device) {
            $device = Device::create([
                'device_id' => (string) Str::uuid(),
                'device_name' => $data['device_name'],
                'hwid' => $data['hwid'],
                'identity_version' => $identityVersion,
                'identity_components' => $identityComponents,
                'machine_secret_hash' => $machineSecretHash ?: null,
                'lifecycle_state' => 'pending_pairing',
                'compliance_status' => 'unknown',
                'policy_hash' => $policyHash,
                'ed25519_pubkey_b64' => $normalizedPubkey,
            ]);
        } else {
            $device->update([
                'device_name' => $data['device_name'],
                'ed25519_pubkey_b64' => $normalizedPubkey,
            ]);
            $this->updateIdentityMetadata($device, (string) $data['hwid'], $identityVersion, $identityComponents, $machineSecretHash);
        }

        $pairToken = $this->jwtSigner->issueForDevice(
            $device->device_id,
            [
                'scope' => 'pair_token',
                'device_name' => $device->device_name,
                'ed25519_pubkey_b64' => $device->ed25519_pubkey_b64,
                'hwid' => $device->hwid,
            ],
            (int) config('jwt.pair_token_ttl', 300),
        );

        if ($errorResponse = $this->attachPairRequestToSession($data, $device, $pairToken)) {
            return $errorResponse;
        }

        return response()->json([
            'pair_token' => $pairToken,
            'expires_at' => now()->addSeconds((int) config('jwt.pair_token_ttl', 300))->toIso8601String(),
            'device_id' => $device->device_id,
        ]);
    }

    public function session(Request $request, string $pairSessionId): JsonResponse
    {
        $user = Auth::user();
        if (! $user) {
            return response()->json(['status' => 'invalid_session'], 401);
        }

        $cached = Cache::get(self::CACHE_PREFIX.$pairSessionId);
        if (! is_array($cached)) {
            return response()->json([
                'status' => 'expired',
                'pair_session_id' => $pairSessionId,
            ], 404);
        }

        $sessionUserId = (string) ($cached['user_id'] ?? '');
        if ($sessionUserId !== '' && $sessionUserId !== (string) $user->id) {
            return response()->json(['status' => 'forbidden'], 403);
        }

        $deviceId = (string) ($cached['device_id'] ?? '');
        $deviceName = (string) ($cached['device_name'] ?? '');
        $pairToken = (string) ($cached['pair_token'] ?? '');

        return response()->json([
            'status' => (string) ($cached['status'] ?? 'pending_agent'),
            'pair_session_id' => $pairSessionId,
            'pair_code' => (string) ($cached['pair_code'] ?? ''),
            'expires_at' => (string) ($cached['expires_at'] ?? ''),
            'device_id' => $deviceId !== '' ? $deviceId : null,
            'device_name' => $deviceName !== '' ? $deviceName : null,
            'device_id_suffix' => $deviceId !== '' ? strtoupper(substr($deviceId, -self::PAIR_CODE_LENGTH)) : null,
            'detected_at' => (string) ($cached['detected_at'] ?? '') ?: null,
            'pair_token' => $pairToken !== '' ? $pairToken : null,
        ]);
    }

    public function confirm(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'pair_token' => ['required', 'string'],
            'pair_session_id' => ['nullable', 'string'],
        ]);

        if ($validator->fails()) {
            return response()->json(['status' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $data = $validator->validated();
        $user = Auth::user();
        if (! $user) {
            return response()->json(['status' => 'invalid_session'], 401);
        }

        $policyHash = (string) config('policy.master_hash');
        if ($policyHash === '') {
            return response()->json(['status' => 'invalid', 'reason' => 'policy_hash_not_configured'], 500);
        }

        try {
            $claims = $this->decodePairToken($data['pair_token']);
        } catch (\Throwable $e) {
            return response()->json(['status' => 'invalid', 'reason' => 'invalid_pair_token'], 401);
        }

        if (($claims['scope'] ?? null) !== 'pair_token') {
            return response()->json(['status' => 'invalid', 'reason' => 'invalid_scope'], 401);
        }

        $cached = null;
        if (! empty($data['pair_session_id'])) {
            $cached = Cache::get(self::CACHE_PREFIX.$data['pair_session_id']);
            if (! is_array($cached)) {
                return response()->json(['status' => 'expired', 'device_id' => null, 'device_name' => null, 'lifecycle_state' => null]);
            }

            $sessionUserId = (string) ($cached['user_id'] ?? '');
            if ($sessionUserId !== '' && $sessionUserId !== (string) $user->id) {
                return response()->json(['status' => 'forbidden'], 403);
            }

            $sessionPairToken = (string) ($cached['pair_token'] ?? '');
            if ($sessionPairToken !== '' && ! hash_equals($sessionPairToken, (string) $data['pair_token'])) {
                return response()->json(['status' => 'invalid', 'reason' => 'pair_token_session_mismatch'], 401);
            }
        }

        $deviceId = (string) ($claims['sub'] ?? '');
        if ($deviceId === '') {
            return response()->json(['status' => 'invalid', 'reason' => 'missing_device_id'], 401);
        }

        $device = Device::find($deviceId);
        if (! $device) {
            $device = Device::create([
                'device_id' => $deviceId,
                'device_name' => $claims['device_name'] ?? 'New Device',
                'hwid' => $claims['hwid'] ?? null,
                'lifecycle_state' => 'offline',
                'compliance_status' => 'unknown',
                'policy_hash' => $policyHash,
                'ed25519_pubkey_b64' => $claims['ed25519_pubkey_b64'] ?? null,
            ]);
        }

        if (! empty($device->user_id) && $device->user_id !== $user->id) {
            return response()->json(['status' => 'conflict', 'device_id' => $device->device_id, 'device_name' => $device->device_name, 'lifecycle_state' => $device->lifecycle_state], 409);
        }

        $deviceName = $claims['device_name'] ?? $device->device_name;
        if (is_array($cached) && ! empty($cached['device_label'])) {
            $deviceName = $cached['device_label'];
        }

        $device->update([
            'user_id' => $user->id,
            'device_name' => $deviceName,
            'lifecycle_state' => in_array($device->lifecycle_state, ['online', 'active'], true) ? $device->lifecycle_state : 'offline',
            'ed25519_pubkey_b64' => isset($claims['ed25519_pubkey_b64'])
                ? $this->normalizePubkey((string) $claims['ed25519_pubkey_b64'])
                : $device->ed25519_pubkey_b64,
        ]);

        $rolePromoted = false;
        if ((string) $user->role === User::ROLE_VIEWER) {
            $user->forceFill(['role' => User::ROLE_OPERATOR])->save();
            $user->refresh();
            $rolePromoted = true;
        }

        $sessionId = $request->attributes->get('jwt_session_id');
        if ($sessionId) {
            $authToken = AuthToken::where('session_id', $sessionId)
                ->where('user_id', $user->id)
                ->whereNull('revoked_at')
                ->first();

            if ($authToken && $authToken->device_fingerprint) {
                $mobileDevice = $this->mobileTracker->touch($user, [
                    'device_fingerprint' => $authToken->device_fingerprint,
                    'push_token' => $authToken->push_token,
                ]);

                if ($mobileDevice) {
                    DeviceLink::firstOrCreate(
                        [
                            'mobile_device_id' => $mobileDevice->id,
                            'device_id' => $device->device_id,
                        ],
                        [
                            'user_id' => $user->id,
                            'linked_via' => 'pair_confirm',
                            'linked_at' => now(),
                        ],
                    );
                }
            }
        }

        $agentJwtTtl = (int) config('jwt.agent_ttl', (int) config('jwt.ttl', 900));
        $agentJwtExpiresAt = now()->addSeconds($agentJwtTtl)->toIso8601String();
        $agentJwt = $this->jwtSigner->issueForDevice($device->device_id, [
            'scope' => 'agent',
            'policy_hash' => $policyHash,
        ], $agentJwtTtl);

        if (! empty($device->ed25519_pubkey_b64)) {
            $this->keySync->push($device);
        }

        if (! empty($data['pair_session_id']) && is_array($cached)) {
            $this->clearPairSession((string) $data['pair_session_id'], $cached);
        }

        $this->pairedWebhook->notify($device, $agentJwt, $agentJwtExpiresAt);

        return response()->json([
            'status' => 'ok',
            'device_id' => $device->device_id,
            'device_name' => $device->device_name,
            'lifecycle_state' => $device->lifecycle_state,
            'user_role' => (string) $user->role,
            'role_promoted' => $rolePromoted,
            'agent_jwt' => $agentJwt,
            'agent_jwt_expires_at' => $agentJwtExpiresAt,
        ]);
    }

    public function agentToken(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'pair_token' => ['required', 'string'],
        ]);

        if ($validator->fails()) {
            return response()->json(['status' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $policyHash = (string) config('policy.master_hash');
        if ($policyHash === '') {
            return response()->json(['status' => 'invalid', 'reason' => 'policy_hash_not_configured'], 500);
        }

        try {
            $claims = $this->decodePairToken($validator->validated()['pair_token']);
        } catch (\Throwable $e) {
            return response()->json(['status' => 'invalid', 'reason' => 'invalid_pair_token'], 401);
        }

        if (($claims['scope'] ?? null) !== 'pair_token') {
            return response()->json(['status' => 'invalid', 'reason' => 'invalid_scope'], 401);
        }

        $deviceId = (string) ($claims['sub'] ?? '');
        if ($deviceId === '') {
            return response()->json(['status' => 'invalid', 'reason' => 'missing_device_id'], 401);
        }

        $device = Device::find($deviceId);
        if (! $device || empty($device->user_id)) {
            return response()->json(['status' => 'invalid', 'reason' => 'device_not_paired'], 409);
        }

        $agentJwtTtl = (int) config('jwt.agent_ttl', (int) config('jwt.ttl', 900));
        $jwt = $this->jwtSigner->issueForDevice($deviceId, [
            'scope' => 'agent',
            'policy_hash' => $policyHash,
        ], $agentJwtTtl);

        return response()->json([
            'status' => 'ok',
            'device_id' => $deviceId,
            'jwt' => $jwt,
        ]);
    }

    /**
     * @param array<string, mixed> $requestData
     */
    private function attachPairRequestToSession(array $requestData, Device $device, string $pairToken): ?JsonResponse
    {
        $rawPairCode = trim((string) ($requestData['pair_code'] ?? ''));
        $pairSessionId = trim((string) ($requestData['pair_session_id'] ?? ''));
        if ($rawPairCode === '' && $pairSessionId === '') {
            return null;
        }

        $pairCode = preg_replace('/\D+/', '', $rawPairCode ?? '') ?? '';
        if ($pairCode === '' && $pairSessionId === '') {
            return response()->json(['status' => 'invalid', 'reason' => 'pair_code_required'], 422);
        }

        if ($pairSessionId === '' && $pairCode !== '') {
            $pairSessionId = (string) Cache::get(self::CODE_CACHE_PREFIX.$pairCode, '');
        }
        if ($pairSessionId === '') {
            return response()->json(['status' => 'invalid', 'reason' => 'pair_session_not_found'], 404);
        }

        $cached = Cache::get(self::CACHE_PREFIX.$pairSessionId);
        if (! is_array($cached)) {
            return response()->json(['status' => 'expired', 'reason' => 'pair_session_expired'], 410);
        }

        $sessionPairCode = preg_replace('/\D+/', '', (string) ($cached['pair_code'] ?? '')) ?? '';
        if ($pairCode !== '' && $sessionPairCode !== '' && ! hash_equals($sessionPairCode, $pairCode)) {
            return response()->json(['status' => 'invalid', 'reason' => 'invalid_pair_code'], 401);
        }

        $status = strtolower((string) ($cached['status'] ?? 'pending_agent'));
        if ($status === 'paired') {
            return response()->json(['status' => 'conflict', 'reason' => 'pair_session_already_used'], 409);
        }

        $expiresAt = $this->resolvePairSessionExpiry($cached);
        if ($expiresAt->isPast()) {
            return response()->json(['status' => 'expired', 'reason' => 'pair_session_expired'], 410);
        }

        $cached['status'] = 'pending_confirmation';
        $cached['pair_token'] = $pairToken;
        $cached['device_id'] = (string) $device->device_id;
        $cached['device_name'] = (string) $device->device_name;
        $cached['detected_at'] = now()->toIso8601String();
        if ($sessionPairCode !== '') {
            $cached['pair_code'] = $sessionPairCode;
            Cache::put(self::CODE_CACHE_PREFIX.$sessionPairCode, $pairSessionId, $expiresAt);
        }

        Cache::put(self::CACHE_PREFIX.$pairSessionId, $cached, $expiresAt);

        return null;
    }

    /**
     * @param array<string, mixed> $cached
     */
    private function clearPairSession(string $pairSessionId, array $cached): void
    {
        Cache::forget(self::CACHE_PREFIX.$pairSessionId);
        $pairCode = trim((string) ($cached['pair_code'] ?? ''));
        if ($pairCode !== '') {
            Cache::forget(self::CODE_CACHE_PREFIX.$pairCode);
        }
    }

    /**
     * @param array<string, mixed> $cached
     */
    private function resolvePairSessionExpiry(array $cached): Carbon
    {
        $raw = trim((string) ($cached['expires_at'] ?? ''));
        if ($raw !== '') {
            try {
                return Carbon::parse($raw);
            } catch (\Throwable $e) {
                // Fallback below.
            }
        }

        return now()->addMinutes(10);
    }

    private function generateUniquePairCode(): string
    {
        for ($attempt = 0; $attempt < 8; $attempt++) {
            $code = str_pad((string) random_int(0, (10 ** self::PAIR_CODE_LENGTH) - 1), self::PAIR_CODE_LENGTH, '0', STR_PAD_LEFT);
            if (! Cache::has(self::CODE_CACHE_PREFIX.$code)) {
                return $code;
            }
        }

        return str_pad((string) random_int(0, (10 ** self::PAIR_CODE_LENGTH) - 1), self::PAIR_CODE_LENGTH, '0', STR_PAD_LEFT);
    }

    private function decodePairToken(string $token): array
    {
        $publicKeyPath = config('jwt.public_key_path');
        if (! is_string($publicKeyPath) || $publicKeyPath === '' || ! file_exists($publicKeyPath)) {
            throw new \RuntimeException('JWT public key not configured');
        }

        $publicKey = file_get_contents($publicKeyPath);
        if ($publicKey === false) {
            throw new \RuntimeException('Unable to read JWT public key');
        }

        $alg = strtoupper((string) config('jwt.alg', 'RS256'));
        if ($alg === 'PS256') {
            $alg = 'RS256';
        }

        $decoded = JWT::decode($token, new Key($publicKey, $alg));

        if (($decoded->iss ?? null) !== config('jwt.issuer')) {
            throw new \RuntimeException('Invalid issuer');
        }
        if (($decoded->aud ?? null) !== config('jwt.audience')) {
            throw new \RuntimeException('Invalid audience');
        }

        return json_decode(json_encode($decoded), true);
    }

    /**
     * @param mixed $raw
     * @return array<string, string>
     */
    private function normalizeIdentityComponents(mixed $raw): array
    {
        if (! is_array($raw)) {
            return [];
        }

        $allowedKeys = ['mb_uuid', 'cpu_id', 'disk_serial', 'primary_mac'];
        $normalized = [];

        foreach ($allowedKeys as $key) {
            $value = trim((string) ($raw[$key] ?? ''));
            if ($value === '') {
                continue;
            }
            $normalized[$key] = strtolower($value);
        }

        return $normalized;
    }

    /**
     * @param array<string, string> $identityComponents
     * @return array{status:string,device?:Device}
     */
    private function findFuzzyIdentityMatch(string $identityVersion, array $identityComponents): array
    {
        $anchor = $identityComponents['mb_uuid'] ?? '';
        if ($anchor === '') {
            return ['status' => 'none'];
        }

        $candidates = Device::query()
            ->where('identity_version', $identityVersion)
            ->whereNotNull('identity_components')
            ->where('identity_components->mb_uuid', $anchor)
            ->get();

        if ($candidates->isEmpty()) {
            return ['status' => 'none'];
        }

        $matches = [];
        foreach ($candidates as $candidate) {
            $stored = $this->normalizeIdentityComponents($candidate->identity_components ?? []);
            if (($stored['mb_uuid'] ?? '') !== $anchor) {
                continue;
            }

            $score = $this->identityMatchScore($stored, $identityComponents);
            if ($score >= 3) {
                $matches[] = ['device' => $candidate, 'score' => $score];
            }
        }

        if (empty($matches)) {
            return ['status' => 'none'];
        }

        usort($matches, fn (array $a, array $b) => $b['score'] <=> $a['score']);
        $topScore = $matches[0]['score'];
        $topMatches = array_values(array_filter($matches, fn (array $m) => $m['score'] === $topScore));
        if (count($topMatches) > 1) {
            return ['status' => 'ambiguous'];
        }

        return ['status' => 'matched', 'device' => $topMatches[0]['device']];
    }

    /**
     * @param array<string, string> $stored
     * @param array<string, string> $incoming
     */
    private function identityMatchScore(array $stored, array $incoming): int
    {
        $score = 0;
        foreach (['mb_uuid', 'cpu_id', 'disk_serial', 'primary_mac'] as $key) {
            if (($stored[$key] ?? '') !== '' && ($incoming[$key] ?? '') !== '' && $stored[$key] === $incoming[$key]) {
                $score++;
            }
        }

        return $score;
    }

    /**
     * @param array<string, string> $identityComponents
     */
    private function updateIdentityMetadata(
        Device $device,
        string $hwid,
        ?string $identityVersion,
        array $identityComponents,
        ?string $machineSecretHash,
    ): void {
        $updates = [];

        $normalizedHwid = trim($hwid);
        if ($normalizedHwid !== '' && $device->hwid !== $normalizedHwid) {
            $updates['hwid'] = $normalizedHwid;
        }

        if (! empty($identityVersion) && $device->identity_version !== $identityVersion) {
            $updates['identity_version'] = $identityVersion;
        }

        if (! empty($identityComponents)) {
            $updates['identity_components'] = $identityComponents;
        }

        if (! empty($machineSecretHash) && $device->machine_secret_hash !== $machineSecretHash) {
            $updates['machine_secret_hash'] = $machineSecretHash;
        }

        if (! empty($updates)) {
            $device->update($updates);
        }
    }

    private function normalizePubkey(string $pubkey): string
    {
        $trimmed = trim($pubkey);
        if ($trimmed === '') {
            return $trimmed;
        }

        $decoded = base64_decode($trimmed, true);
        if ($decoded === false) {
            $padding = (4 - (strlen($trimmed) % 4)) % 4;
            $decoded = base64_decode($trimmed.str_repeat('=', $padding), true);
        }

        if ($decoded === false) {
            return rtrim($trimmed, '=');
        }

        return base64_encode($decoded);
    }

    private function pubkeysMatch(string $stored, string $incoming): bool
    {
        return hash_equals($this->normalizePubkey($stored), $this->normalizePubkey($incoming));
    }
}
