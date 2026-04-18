<?php

namespace App\Services\Security;

use App\Models\Command;
use Illuminate\Support\Facades\Cache;

final class MonotonicCounter
{
    /**
     * Atomically increments and returns a monotonic counter.
     *
     * Backends:
     * - Redis: atomic INCR
     * - Database cache: atomic-ish per DB semantics
     */
    public function next(string $name): int
    {
        $key = 'system002:counter:'.$name;

        // Ensure key exists for cache stores that require explicit initialization.
        // For command dispatch sequencing we must never go backwards across restarts;
        // bootstrap from the persisted max(server_seq) if cache was reset.
        if (Cache::get($key) === null) {
            $seed = 0;

            if ($name === 'fastapi_dispatch') {
                $persistedMax = (int) (Command::query()->max('server_seq') ?? 0);
                if ($persistedMax > 0) {
                    $seed = $persistedMax;
                }
            }

            Cache::forever($key, $seed);
        }

        return (int) Cache::increment($key);
    }
}
