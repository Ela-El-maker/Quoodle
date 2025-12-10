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

class TokenController extends Controller
{
    public function __construct(private readonly JWTSigner $jwtSigner)
    {
    }

    public function refresh(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'refresh_token' => ['required', 'string'],
        ]);

        if ($validator->fails()) {
            return response()->json(['message' => 'validation_error', 'errors' => $validator->errors()], 422);
        }

        $refresh = $validator->validated()['refresh_token'];
        $token = AuthToken::where('refresh_token_hash', hash('sha256', $refresh))->first();
        if (! $token || $token->expires_at->isPast()) {
            return response()->json(['message' => 'invalid_refresh'], 401);
        }

        $user = User::find($token->user_id);
        if (! $user) {
            return response()->json(['message' => 'invalid_refresh'], 401);
        }

        $sessionId = $token->session_id;
        $newRefresh = Str::uuid()->toString().Str::random(32);
        $token->update([
            'refresh_token_hash' => hash('sha256', $newRefresh),
            'expires_at' => now()->addSeconds((int) config('jwt.refresh_ttl', 3600)),
        ]);

        return response()->json([
            'jwt' => $this->jwtSigner->issueForUser($user, $sessionId),
            'refresh_token' => $newRefresh,
            'expires_in' => (int) config('jwt.ttl', 3600),
        ]);
    }

    public function logout(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'session_id' => ['required', 'string'],
            'all_devices' => ['required', 'boolean'],
        ]);

        if ($validator->fails()) {
            return response()->json(['errors' => $validator->errors()], 422);
        }

        $data = $validator->validated();
        $query = AuthToken::where('session_id', $data['session_id']);
        if ($data['all_devices']) {
            $query = AuthToken::query();
        }
        $query->update(['revoked_at' => now()]);

        return response()->json(['status' => 'ok']);
    }
}
