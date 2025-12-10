<?php

namespace App\Services\JWT;

class JWKSManager
{
    public function publish(array $keys): array
    {
        return [
            'keys' => $keys,
        ];
    }
}
