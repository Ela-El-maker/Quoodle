<?php

namespace App\Http\Controllers\Devices;

use App\Http\Controllers\Controller;
use App\Models\AuthToken;
use App\Models\Device;
use App\Models\DeviceLink;
use App\Services\Devices\FastApiDeviceKeySync;
use App\Services\Devices\FastApiDevicePairedWebhook;
use App\Services\JWT\JWTSigner;
use App\Services\Mobile\MobileDeviceTracker;
use Firebase\JWT\JWT;
use Firebase\JWT\Key;
use Illuminate\Support\Facades\Auth;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;

class PairingController extends Controller
{
    private const CACHE_PREFIX = 'pair_session_';

    public function __construct(
        private readonly JWTSigner $jwtSigner,
        private readonly FastApiDeviceKeySync $keySync,
        private readonly FastApiDevicePairedWebhook $pairedWebhook,
        private readonly MobileDeviceTracker $mobileTracker,
    ) {
    }

    public function init(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'device_label' => ['nullable', 'string', 'max:190'],
        ]);

        if ($validator->fails()) {
            return response()->json(['message' => 'validation_error', 'errors' => $validator->errors()], 422);
        }

        $pairSessionId = Str::uuid()->toString();
        Cache::put(self::CACHE_PREFIX.$pairSessionId, [
            'pair_session_id' => $pairSessionId,
            'device_label' => $validator->validated()['device_label'] ?? null,
        ], now()->addMinutes(10));

        return response()->json([
            'pair_session_id' => $pairSessionId,
            'expires_at' => now()->addMinutes(10)->toIso8601String(),
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
        ]);

        if ($validator->fails()) {
            return response()->json(['status' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $data = $validator->validated();
        $normalizedPubkey = $this->normalizePubkey((string) $data['pubkey']);
        $policyHash = (string) config('policy.master_hash');
        if ($policyHash === '') {
            return response()->json(['status' => 'invalid', 'reason' => 'policy_hash_not_configured'], 500);
        }

        $device = Device::where('hwid', $data['hwid'])->first();

        if ($device && ! empty($device->user_id)) {
            if (! empty($device->ed25519_pubkey_b64) && $this->pubkeysMatch((string) $device->ed25519_pubkey_b64, $normalizedPubkey)) {
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

        return response()->json([
            'pair_token' => $pairToken,
            'expires_at' => now()->addSeconds((int) config('jwt.pair_token_ttl', 300))->toIso8601String(),
            'device_id' => $device->device_id,
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
            $cached = Cache::pull(self::CACHE_PREFIX.$data['pair_session_id']);
            if (! $cached) {
                return response()->json(['status' => 'expired', 'device_id' => null, 'device_name' => null, 'lifecycle_state' => null]);
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

        $agentJwtTtl = (int) config('jwt.ttl', 900);
        $agentJwtExpiresAt = now()->addSeconds($agentJwtTtl)->toIso8601String();
        $agentJwt = $this->jwtSigner->issueForDevice($device->device_id, [
            'scope' => 'agent',
            'policy_hash' => $policyHash,
        ], $agentJwtTtl);

        if (! empty($device->ed25519_pubkey_b64)) {
            $this->keySync->push($device);
        }

        $this->pairedWebhook->notify($device, $agentJwt, $agentJwtExpiresAt);

        return response()->json([
            'status' => 'ok',
            'device_id' => $device->device_id,
            'device_name' => $device->device_name,
            'lifecycle_state' => $device->lifecycle_state,
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

        $jwt = $this->jwtSigner->issueForDevice($deviceId, [
            'scope' => 'agent',
            'policy_hash' => $policyHash,
        ]);

        return response()->json([
            'status' => 'ok',
            'device_id' => $deviceId,
            'jwt' => $jwt,
        ]);
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
