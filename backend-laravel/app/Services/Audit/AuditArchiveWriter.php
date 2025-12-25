<?php

namespace App\Services\Audit;

use App\Models\Command;

final class AuditArchiveWriter
{
    public function appendCommandEnvelope(Command $command): void
    {
        $path = (string) config('audit.archive_path');
        if ($path === '') {
            return;
        }

        $row = [
            'timestamp' => now()->toIso8601String(),
            'command_id' => $command->id,
            'device_id' => $command->device_id,
            'server_seq' => $command->server_seq,
            'method' => $command->method,
            'sensitive' => (bool) $command->sensitive,
            'request_sig' => $command->request_sig,
            'envelope_sig' => $command->envelope_sig,
            'envelope' => $command->envelope,
        ];

        $line = json_encode($row, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
        if (! is_string($line)) {
            return;
        }

        // Append-only write (best-effort). Use a file lock to avoid interleaving.
        $dir = dirname($path);
        if (! is_dir($dir)) {
            @mkdir($dir, 0775, true);
        }

        $fh = @fopen($path, 'ab');
        if (! $fh) {
            return;
        }

        try {
            @flock($fh, LOCK_EX);
            @fwrite($fh, $line."\n");
        } finally {
            @flock($fh, LOCK_UN);
            @fclose($fh);
        }
    }
}
