<?php

return [
    // Write-only "black box" archive of signed envelopes (JSONL format).
    // One JSON object per line.
    'archive_path' => env('AUDIT_ARCHIVE_PATH', storage_path('app/audit_archive.jsonl')),
];
