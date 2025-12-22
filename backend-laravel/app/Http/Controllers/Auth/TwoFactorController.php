<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use App\Models\AuthToken;
use App\Models\User;
use App\Services\JWT\JWTSigner;
use App\Services\Security\TOTPService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;

class TwoFactorController extends Controller
{
    public function __construct(
        private readonly JWTSigner $jwtSigner,
        private readonly TOTPService $totp,
    )
    {
    }

    public function verify(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'user_id' => ['required', 'string'],
            'session_id' => ['required', 'string'],
            'two_factor_code' => ['required', 'string'],
        ]);

        if ($validator->fails()) {
            return response()->json(['status' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $data = $validator->validated();
        $user = User::find($data['user_id']);
        if (! $user) {
            return response()->json(['status' => 'invalid'], 404);
        }

        if (! $user->two_factor_enabled || empty($user->two_factor_secret)) {
            return response()->json(['status' => 'require_enrollment'], 409);
        }

        $ok = $this->totp->verify($user->two_factor_secret, $data['two_factor_code']);
        if (! $ok) {
            return response()->json(['status' => 'invalid'], 401);
        }

        $refreshToken = Str::uuid()->toString().Str::random(32);
        AuthToken::create([
            'user_id' => $user->id,
            'session_id' => $data['session_id'],
            'device_fingerprint' => null,
            'push_token' => null,
            'refresh_token_hash' => hash('sha256', $refreshToken),
            'expires_at' => now()->addSeconds((int) config('jwt.refresh_ttl', 3600)),
        ]);

        return response()->json([
            'status' => 'ok',
            'jwt' => $this->jwtSigner->issueForUser($user, $data['session_id']),
            'refresh_token' => $refreshToken,
        ]);
    }

    public function setup(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'user_id' => ['required', 'string'],
            'session_id' => ['required', 'string'],
        ]);

        if ($validator->fails()) {
            return response()->json(['status' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $data = $validator->validated();
        $token = AuthToken::where('user_id', $data['user_id'])
            ->where('session_id', $data['session_id'])
            ->whereNull('revoked_at')
            ->where('expires_at', '>', now())
            ->first();

        if (! $token) {
            return response()->json(['status' => 'invalid_session'], 401);
        }

        $user = User::find($data['user_id']);
        if (! $user) {
            return response()->json(['status' => 'invalid'], 404);
        }

        $secret = $this->totp->generateSecretBase32();
        $issuer = (string) config('app.name', 'System002');
        $label = $user->email ?: $user->id;
        $uri = $this->totp->buildOtpAuthUri($issuer, $label, $secret);

        $user->update([
            'two_factor_secret' => $secret,
            'two_factor_enabled' => false,
        ]);

        return response()->json([
            'status' => 'ok',
            'secret' => $secret,
            'otpauth_uri' => $uri,
        ]);
    }

    public function confirm(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'user_id' => ['required', 'string'],
            'session_id' => ['required', 'string'],
            'two_factor_code' => ['required', 'string'],
        ]);

        if ($validator->fails()) {
            return response()->json(['status' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $data = $validator->validated();
        $token = AuthToken::where('user_id', $data['user_id'])
            ->where('session_id', $data['session_id'])
            ->whereNull('revoked_at')
            ->where('expires_at', '>', now())
            ->first();

        if (! $token) {
            return response()->json(['status' => 'invalid_session'], 401);
        }

        $user = User::find($data['user_id']);
        if (! $user) {
            return response()->json(['status' => 'invalid'], 404);
        }

        if (empty($user->two_factor_secret)) {
            return response()->json(['status' => 'require_setup'], 409);
        }

        $ok = $this->totp->verify($user->two_factor_secret, $data['two_factor_code']);
        if (! $ok) {
            return response()->json(['status' => 'invalid'], 401);
        }

        $user->update([
            'two_factor_enabled' => true,
        ]);

        return response()->json([
            'status' => 'ok',
            'two_factor_enabled' => true,
        ]);
    }
}
