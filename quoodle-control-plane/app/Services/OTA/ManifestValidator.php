<?php

namespace App\Services\OTA;

class ManifestValidator
{
    public function validate(array $manifest): bool
    {
        $required = ['release_id', 'version', 'sha256', 'signature', 'min_agent_version', 'published_at'];
        foreach ($required as $key) {
            if (! isset($manifest[$key]) || empty($manifest[$key])) {
                return false;
            }
        }

        return true;
    }
}
