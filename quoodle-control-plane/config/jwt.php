<?php

return [
    'issuer' => env('JWT_ISSUER', 'secure-device-control-system'),
    'audience' => env('JWT_AUDIENCE', 'secure-device-clients'),
    'kid' => env('JWT_KID', 'K1'),
    'alg' => env('JWT_ALG', 'PS256'),
    'ttl' => (int) env('JWT_TTL', 900),
    'refresh_ttl' => (int) env('JWT_REFRESH_TTL', 3600),
    'private_key_path' => (function (): string {
        $p = env('JWT_PRIVATE_KEY_PATH');
        if (is_string($p) && $p !== '') {
            // If env path is relative, resolve relative to the Laravel base path (not CWD).
            if (! preg_match('/^(?:[A-Za-z]:\\\\|\/|\\\\\\\)/', $p)) {
                return base_path($p);
            }
            return $p;
        }
        return storage_path('app/private/jwt_private.pem');
    })(),
    'public_key_path' => (function (): string {
        $p = env('JWT_PUBLIC_KEY_PATH');
        if (is_string($p) && $p !== '') {
            if (! preg_match('/^(?:[A-Za-z]:\\\\|\/|\\\\\\\)/', $p)) {
                return base_path($p);
            }
            return $p;
        }
        return storage_path('app/private/jwt_public.pem');
    })(),
];
