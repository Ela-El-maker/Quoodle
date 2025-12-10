<?php

namespace App\Services\OTA;

class ManifestValidator
{
    public function validate(array $manifest): bool
    {
        return isset($manifest['sha256']) && isset($manifest['version']);
    }
}
