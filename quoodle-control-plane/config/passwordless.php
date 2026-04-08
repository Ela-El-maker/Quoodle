<?php

return [
    'otp' => [
        'digits' => (int) env('AUTH_OTP_DIGITS', 6),
        'ttl_seconds' => (int) env('AUTH_OTP_TTL_SECONDS', 600),
        'resend_cooldown_seconds' => (int) env('AUTH_OTP_RESEND_COOLDOWN_SECONDS', 60),
        'max_attempts' => (int) env('AUTH_OTP_MAX_ATTEMPTS', 5),
        'request_ip_max_per_minute' => (int) env('AUTH_OTP_REQUEST_IP_MAX_PER_MINUTE', 20),
        'request_email_max_per_minute' => (int) env('AUTH_OTP_REQUEST_EMAIL_MAX_PER_MINUTE', 6),
    ],
];

