<?php

namespace App\Services\AuditTrail;

class AuditHasher
{
    public function hash(string $prevHash, string $payloadHash): string
    {
        return hash('sha256', $prevHash.$payloadHash);
    }
}
