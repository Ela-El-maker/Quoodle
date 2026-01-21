<?php

return [
    // Seconds to wait after a sensitive command before trusting telemetry as "ground truth".
    'state_verify_delay_seconds' => (int) env('STATE_VERIFY_DELAY_SECONDS', 10),
    // Default role assigned on registration (viewer/operator/admin).
    'default_user_role' => env('DEFAULT_USER_ROLE', 'viewer'),
];
