<?php

namespace App\Services\OTA;

class ReleaseManager
{
    public function create(array $data): array
    {
        return [
            'release_id' => $data['release_id'] ?? '',
            'version' => $data['version'] ?? '',
            'manifest_url' => $data['manifest_url'] ?? '',
            'signature_url' => $data['signature_url'] ?? '',
            'sha256' => $data['sha256'] ?? '',
        ];
    }
}
