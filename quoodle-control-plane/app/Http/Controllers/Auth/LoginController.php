<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use App\Models\AuthToken;
use App\Models\User;
use App\Services\JWT\JWTSigner;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;

class LoginController extends Controller
{
    public function __construct(private readonly JWTSigner $jwtSigner)
    {
    }

    public function login(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'email' => ['required', 'email'],
            'password' => ['required', 'string'],
            'device_fingerprint' => ['required', 'string', 'max:255'],
            'push_token' => ['nullable', 'string', 'max:512'],
            'two_factor_code' => ['nullable', 'string', 'max:64'],
        ]);

        if ($validator->fails()) {
            return response()->json([
                'message' => 'validation_error',
                'errors' => $validator->errors(),
            ], 422);
        }

        $data = $validator->validated();
        $user = User::where('email', $data['email'])->first();

        if (! $user || ! Hash::check($data['password'], $user->password)) {
            return response()->json([
                'message' => 'invalid_credentials',
            ], 401);
        }

        // TODO: Integrate 2FA per spec in later phase.
        $twoFactorRequired = false;
        $twoFactorPending = false;

        $sessionId = Str::uuid()->toString();
        $refreshToken = Str::uuid()->toString().Str::random(32);
        $refreshExpiresAt = now()->addSeconds((int) config('jwt.refresh_ttl', 3600));

        AuthToken::create([
            'user_id' => $user->id,
            'session_id' => $sessionId,
            'device_fingerprint' => $data['device_fingerprint'] ?? null,
            'push_token' => $data['push_token'] ?? null,
            'refresh_token_hash' => hash('sha256', $refreshToken),
            'expires_at' => $refreshExpiresAt,
        ]);

        $jwt = $this->jwtSigner->issueForUser($user, $sessionId);

        return response()->json([
            'jwt' => $jwt,
            'refresh_token' => $refreshToken,
            'session_id' => $sessionId,
            'two_factor_pending' => $twoFactorPending,
            'two_factor_required' => $twoFactorRequired,
            'user_id' => $user->id,
        ]);
    }
}
