<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use App\Models\AuthToken;
use App\Services\Mobile\MobileDeviceTracker;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Validator;

class SessionController extends Controller
{
    public function __construct(private readonly MobileDeviceTracker $mobileTracker)
    {
    }

    public function updatePushToken(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'push_token' => ['required', 'string', 'max:512'],
            'platform' => ['nullable', 'string', 'max:64'],
            'os_version' => ['nullable', 'string', 'max:64'],
            'device_model' => ['nullable', 'string', 'max:128'],
            'app_version' => ['nullable', 'string', 'max:64'],
        ]);

        if ($validator->fails()) {
            return response()->json([
                'status' => 'invalid',
                'errors' => $validator->errors(),
            ], 422);
        }

        $sessionId = $request->attributes->get('jwt_session_id');
        $user = Auth::user();

        if (! $sessionId || ! $user) {
            return response()->json(['status' => 'invalid_session'], 401);
        }

        $token = AuthToken::where('session_id', $sessionId)
            ->where('user_id', $user->id)
            ->whereNull('revoked_at')
            ->first();

        if (! $token) {
            return response()->json(['status' => 'invalid_session'], 401);
        }

        $token->update([
            'push_token' => $validator->validated()['push_token'],
        ]);

        $this->mobileTracker->touch($user, [
            'device_fingerprint' => $token->device_fingerprint,
            'push_token' => $validator->validated()['push_token'],
            'platform' => $validator->validated()['platform'] ?? null,
            'os_version' => $validator->validated()['os_version'] ?? null,
            'device_model' => $validator->validated()['device_model'] ?? null,
            'app_version' => $validator->validated()['app_version'] ?? null,
        ]);

        return response()->json([
            'status' => 'ok',
            'session_id' => $sessionId,
        ]);
    }
}
