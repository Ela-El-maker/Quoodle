<?php

namespace App\Services\Security;

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
        if (Cache::get($key) === null) {
            Cache::forever($key, 0);
        }

        return (int) Cache::increment($key);
    }
}
