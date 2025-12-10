<?php

namespace App\Services\CA;

class CSRGenerator
{
    public function generate(string $commonName): array
    {
        return [
            'csr' => 'csr-placeholder-'.$commonName,
            'private_key' => 'private-key-placeholder',
        ];
    }
}
