<?php

namespace App\Services\JWT;

class KeyRotationService
{
    public function rotate(): array
    {
        // Simulated key rotation for academic use.
        return [
            'kid' => uniqid('kid_', true),
            'public' => 'public-key-placeholder',
            'private' => 'private-key-placeholder',
        ];
    }
}
