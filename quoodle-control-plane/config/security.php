<?php

return [
    // Seconds to wait after a sensitive command before trusting telemetry as "ground truth".
    'state_verify_delay_seconds' => (int) env('STATE_VERIFY_DELAY_SECONDS', 10),
    // Default role assigned on registration (viewer/operator/admin).
    'default_user_role' => env('DEFAULT_USER_ROLE', 'viewer'),
    // Command TTL used when clients do not supply a TTL.
    'command_ttl_seconds' => (int) env('COMMAND_TTL_SECONDS', 300),
    // Grace period before expiring commands (covers webhook retry window).
    'command_expiry_grace_seconds' => (int) env('COMMAND_EXPIRY_GRACE_SECONDS', 120),
];
