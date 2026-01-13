<?php

return [
    // Master policy hash expected by the control-plane for enrolled devices.
    // Keep in sync with FastAPI's POLICY_HASH for local dev.
    'master_hash' => env('POLICY_HASH', 'sha256:policy_placeholder'),
];
