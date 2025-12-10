<?php

namespace App\Services\AuditTrail;

class AuditWriter
{
    public function hashPayload(string $prevHash, string $payloadHash): string
    {
        return hash('sha256', $prevHash.$payloadHash);
    }
}
