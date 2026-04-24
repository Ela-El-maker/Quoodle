<?php

return [
    'global_enabled' => (bool) env('AI_GLOBAL_ENABLED', false),
    'device_copilot_enabled' => (bool) env('AI_DEVICE_COPILOT_ENABLED', false),
    'provider_qwen_enabled' => (bool) env('AI_PROVIDER_QWEN_ENABLED', false),
    'default_tenant_id' => env('AI_DEFAULT_TENANT_ID', 'default'),
    'sidecar' => [
        'base_url' => env('AI_SIDECAR_BASE_URL', 'http://ai-sidecar:8000'),
        'service_token' => env('AI_SIDECAR_SERVICE_TOKEN', ''),
        'timeout_seconds' => (float) env('AI_SIDECAR_TIMEOUT_SECONDS', 15),
    ],
];

