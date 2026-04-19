<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use App\Mail\AuthOtpCodeMail;
use App\Models\OtpChallenge;
use App\Models\User;
use App\Services\Auth\AuthSessionService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Mail;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;

class OtpAuthController extends Controller
{
    public function __construct(private readonly AuthSessionService $sessionService)
    {
    }

    public function requestOtp(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'email' => ['required', 'email', 'max:190'],
        ]);

        if ($validator->fails()) {
            return response()->json([
                'message' => 'validation_error',
                'errors' => $validator->errors(),
            ], 422);
        }

        $email = strtolower(trim((string) $validator->validated()['email']));
        $ip = (string) ($request->ip() ?? 'unknown');
        $ipKey = 'otp:request:ip:'.sha1($ip);
        $emailKey = 'otp:request:email:'.sha1($email);
        $ipMax = (int) config('passwordless.otp.request_ip_max_per_minute', 20);
        $emailMax = (int) config('passwordless.otp.request_email_max_per_minute', 6);

        if (RateLimiter::tooManyAttempts($ipKey, $ipMax) || RateLimiter::tooManyAttempts($emailKey, $emailMax)) {
            return response()->json([
                'message' => 'rate_limited',
            ], 429);
        }

        RateLimiter::hit($ipKey, 60);
        RateLimiter::hit($emailKey, 60);

        $cooldownSeconds = (int) config('passwordless.otp.resend_cooldown_seconds', 60);
        $activeChallenge = OtpChallenge::query()
            ->where('email', $email)
            ->whereNull('consumed_at')
            ->where('expires_at', '>', now())
            ->latest()
            ->first();

        if ($activeChallenge && $activeChallenge->resend_available_at->isFuture()) {
            return response()->json([
                'status' => 'otp_sent',
                'challenge_id' => $activeChallenge->id,
                'resend_after_seconds' => now()->diffInSeconds($activeChallenge->resend_available_at),
            ]);
        }

        $digits = (int) config('passwordless.otp.digits', 6);
        $otpCode = str_pad((string) random_int(0, (10 ** $digits) - 1), $digits, '0', STR_PAD_LEFT);
        $ttlSeconds = (int) config('passwordless.otp.ttl_seconds', 600);
        $maxAttempts = (int) config('passwordless.otp.max_attempts', 5);

        $user = User::query()->where('email', $email)->first();
        $challenge = OtpChallenge::create([
            'user_id' => $user?->id,
            'email' => $email,
            'otp_hash' => Hash::make($otpCode),
            'attempts' => 0,
            'max_attempts' => $maxAttempts,
            'expires_at' => now()->addSeconds($ttlSeconds),
            'resend_available_at' => now()->addSeconds($cooldownSeconds),
            'last_sent_at' => now(),
            'request_ip' => $ip,
            'user_agent' => substr((string) $request->userAgent(), 0, 512),
        ]);

        Mail::to($email)->send(new AuthOtpCodeMail($otpCode, (int) ceil($ttlSeconds / 60)));

        return response()->json([
            'status' => 'otp_sent',
            'challenge_id' => $challenge->id,
            'resend_after_seconds' => $cooldownSeconds,
        ]);
    }

    public function verifyOtp(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'email' => ['required', 'email', 'max:190'],
            'challenge_id' => ['required', 'string', 'max:64'],
            'otp' => ['required', 'string', 'min:4', 'max:12'],
            'device_fingerprint' => ['nullable', 'string', 'max:255'],
            'push_token' => ['nullable', 'string', 'max:512'],
        ]);

        if ($validator->fails()) {
            return response()->json([
                'message' => 'validation_error',
                'errors' => $validator->errors(),
            ], 422);
        }

        $data = $validator->validated();
        $email = strtolower(trim((string) $data['email']));

        $challenge = OtpChallenge::query()
            ->where('id', $data['challenge_id'])
            ->where('email', $email)
            ->first();

        if (! $challenge || $challenge->consumed_at !== null || $challenge->expires_at->isPast()) {
            return response()->json(['message' => 'invalid_otp'], 401);
        }

        if ($challenge->attempts >= $challenge->max_attempts) {
            return response()->json(['message' => 'invalid_otp'], 401);
        }

        $challenge->attempts += 1;

        if (! Hash::check((string) $data['otp'], $challenge->otp_hash)) {
            $challenge->save();
            return response()->json(['message' => 'invalid_otp'], 401);
        }

        $user = $challenge->user_id ? User::query()->find($challenge->user_id) : null;
        if (! $user || strcasecmp((string) $user->email, $email) !== 0) {
            $user = User::query()->where('email', $email)->first();
        }

        if (! $user) {
            $user = User::create([
                'display_name' => $this->displayNameFromEmail($email),
                'email' => $email,
                'role' => User::ROLE_VIEWER,
                'account_status' => User::STATUS_ACTIVE,
                'two_factor_enabled' => false,
            ]);
        }

        if (method_exists($user, 'isActive') && ! $user->isActive()) {
            return response()->json(['message' => 'account_inactive'], 403);
        }

        if (strcasecmp((string) $user->email, $email) !== 0) {
            $challenge->consumed_at = now();
            $challenge->save();
            return response()->json(['message' => 'invalid_otp'], 401);
        }

        if ((string) ($challenge->user_id ?? '') !== (string) $user->id) {
            $challenge->user_id = $user->id;
        }
        $challenge->consumed_at = now();
        $challenge->save();

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
