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

class RegisterController extends Controller
{
    public function __construct(private readonly JWTSigner $jwtSigner)
    {
    }

    public function register(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'display_name' => ['required', 'string', 'max:120'],
            'email' => ['required', 'email', 'max:190', 'unique:users,email'],
            'password' => ['required', 'string', 'min:8'],
            'pubkey' => ['required', 'string', 'max:1024'],
        ]);

        if ($validator->fails()) {
            return response()->json([
                'message' => 'validation_error',
                'errors' => $validator->errors(),
            ], 422);
        }

        $data = $validator->validated();

        $user = User::create([
            'display_name' => $data['display_name'],
            'email' => $data['email'],
            'password' => Hash::make($data['password']),
            'public_key' => $data['pubkey'],
        ]);

        $sessionId = Str::uuid()->toString();
        $refreshToken = Str::uuid()->toString().Str::random(32);
        $refreshExpiresAt = now()->addSeconds((int) config('jwt.refresh_ttl', 3600));

        AuthToken::create([
            'user_id' => $user->id,
            'session_id' => $sessionId,
            'device_fingerprint' => null,
            'push_token' => null,
            'refresh_token_hash' => hash('sha256', $refreshToken),
            'expires_at' => $refreshExpiresAt,
        ]);

        $jwt = $this->jwtSigner->issueForUser($user, $sessionId);

        return response()->json([
            'jwt' => $jwt,
            'refresh_token' => $refreshToken,
            'requires_2fa_enrollment' => false,
            'user_id' => $user->id,
        ], 201);
    }
}
