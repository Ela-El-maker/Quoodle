<?php

namespace App\Services\Security;

use JsonException;

final class Ed25519CanonicalJson
{
    /**
     * Canonicalize PHP data to a deterministic JSON string:
     * - Objects (associative arrays) have keys sorted lexicographically
     * - Arrays (lists) preserve element order
     * - No whitespace
     */
    public static function encode(mixed $value): string
    {
        $normalized = self::sortKeysRecursive($value);

        try {
            return json_encode(
                $normalized,
                JSON_THROW_ON_ERROR
                | JSON_UNESCAPED_SLASHES
                | JSON_UNESCAPED_UNICODE
                | JSON_PRESERVE_ZERO_FRACTION
            );
        } catch (JsonException $e) {
            throw $e;
        }
    }

    /** Remove any key named 'sig' anywhere in the structure. */
    public static function stripSig(mixed $value): mixed
    {
        if (is_array($value)) {
            $out = [];
            foreach ($value as $k => $v) {
                if ($k === 'sig') {
                    continue;
                }
                $out[$k] = self::stripSig($v);
            }
            return $out;
        }

        return $value;
    }

    private static function sortKeysRecursive(mixed $value): mixed
    {
        if (! is_array($value)) {
            return $value;
        }

        // Detect list vs associative array
        $isList = array_is_list($value);

        if ($isList) {
            $out = [];
            foreach ($value as $v) {
                $out[] = self::sortKeysRecursive($v);
            }
            return $out;
        }

        $out = [];
        $keys = array_keys($value);
        sort($keys, SORT_STRING);
        foreach ($keys as $k) {
            $out[$k] = self::sortKeysRecursive($value[$k]);
        }
        return $out;
    }
}
