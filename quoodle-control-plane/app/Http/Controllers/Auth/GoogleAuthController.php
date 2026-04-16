<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Services\Auth\AuthSessionService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Http;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;

class GoogleAuthController extends Controller
{
    public function __construct(private readonly AuthSessionService $sessionService)
    {
    }

    public function exchange(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'code' => ['required', 'string'],
            'redirect_uri' => ['required', 'url'],
            'device_fingerprint' => ['nullable', 'string', 'max:255'],
            'push_token' => ['nullable', 'string', 'max:512'],
        ]);

        if ($validator->fails()) {
            return response()->json([
                'message' => 'validation_error',
                'errors' => $validator->errors(),
            ], 422);
        }

        $clientId = (string) config('services.google.client_id');
        $clientSecret = (string) config('services.google.client_secret');
        if ($clientId === '' || $clientSecret === '') {
            return response()->json(['message' => 'google_auth_not_configured'], 500);
        }

        $data = $validator->validated();
        $tokenResponse = Http::asForm()->post((string) config('services.google.token_url'), [
            'code' => (string) $data['code'],
            'client_id' => $clientId,
            'client_secret' => $clientSecret,
            'redirect_uri' => (string) $data['redirect_uri'],
            'grant_type' => 'authorization_code',
        ]);

        if (! $tokenResponse->ok()) {
            return response()->json(['message' => 'invalid_google_code'], 401);
        }

        $accessToken = (string) $tokenResponse->json('access_token', '');
        if ($accessToken === '') {
            return response()->json(['message' => 'invalid_google_code'], 401);
        }

        $userInfoResponse = Http::withToken($accessToken)->get((string) config('services.google.userinfo_url'));
        if (! $userInfoResponse->ok()) {
            return response()->json(['message' => 'invalid_google_userinfo'], 401);
        }

        $email = strtolower(trim((string) $userInfoResponse->json('email', '')));
        $emailVerified = (bool) $userInfoResponse->json('email_verified', false);

        if ($email === '' || ! $emailVerified) {
            return response()->json(['message' => 'google_email_not_verified'], 401);
        }

        $user = User::query()->where('email', $email)->first();
        if (! $user) {
            $displayName = trim((string) $userInfoResponse->json('name', ''));
            if ($displayName === '') {
                $displayName = $this->displayNameFromEmail($email);
            }

            $user = User::create([
                'display_name' => $displayName,
                'email' => $email,
                'role' => User::ROLE_VIEWER,
                'two_factor_enabled' => false,
            ]);
        }

        return response()->json($this->sessionService->issueForUser(
            $user,
            $data['device_fingerprint'] ?? null,
            $data['push_token'] ?? null,
        ));
    }

    private function displayNameFromEmail(string $email): string
    {
        $localPart = explode('@', $email)[0] ?? 'User';
        $normalized = Str::of($localPart)
            ->replace(['.', '_', '-'], ' ')
            ->squish()
            ->title()
            ->toString();

        return $normalized !== '' ? $normalized : 'User';
    }
}
