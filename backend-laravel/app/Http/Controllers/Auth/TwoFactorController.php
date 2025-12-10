<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use App\Models\AuthToken;
use App\Models\User;
use App\Services\JWT\JWTSigner;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;

class TwoFactorController extends Controller
{
    public function __construct(private readonly JWTSigner $jwtSigner)
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

        // In this academic simulation any non-empty code is accepted.
        if (empty($data['two_factor_code'])) {
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
}
