<?php

return [
    'issuer' => env('JWT_ISSUER', 'secure-device-control-system'),
    'audience' => env('JWT_AUDIENCE', 'secure-device-clients'),
    'kid' => env('JWT_KID', 'K1'),
    'alg' => env('JWT_ALG', 'PS256'),
    'ttl' => (int) env('JWT_TTL', 900),
    'refresh_ttl' => (int) env('JWT_REFRESH_TTL', 3600),
    'private_key_path' => env('JWT_PRIVATE_KEY_PATH', storage_path('app/private/jwt_private.pem')),
    'public_key_path' => env('JWT_PUBLIC_KEY_PATH', storage_path('app/private/jwt_public.pem')),
];
