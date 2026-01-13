<?php

namespace App\Services\OTA;

class ReleaseManager
{
    public function create(array $data): array
    {
        $channels = $data['channels'] ?? ['dev'];
        $rollout = $data['rollout'] ?? ['percentage' => 10, 'region' => 'global'];

        return [
            'release_id' => $data['release_id'] ?? '',
            'version' => $data['version'] ?? '',
            'manifest_url' => $data['manifest_url'] ?? '',
            'signature_url' => $data['signature_url'] ?? '',
            'sha256' => $data['sha256'] ?? '',
            'sbom_url' => $data['sbom_url'] ?? null,
            'provenance_url' => $data['provenance_url'] ?? null,
            'channels' => $channels,
            'rollout' => $rollout,
        ];
    }
}
