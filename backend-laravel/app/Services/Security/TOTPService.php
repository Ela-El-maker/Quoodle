<?php

namespace App\Services\Security;

use RuntimeException;

final class TOTPService
{
    public function __construct(
        private readonly int $periodSeconds = 30,
        private readonly int $digits = 6,
        private readonly string $algo = 'sha1',
    ) {
        if ($this->digits < 6 || $this->digits > 10) {
            throw new RuntimeException('digits must be between 6 and 10');
        }
        if (! in_array($this->algo, ['sha1', 'sha256', 'sha512'], true)) {
            throw new RuntimeException('Unsupported algo');
        }
    }

    /**
     * Verify a user-provided TOTP code against a Base32 secret.
     */
    public function verify(string $secretBase32, string $code, int $window = 1, ?int $unixTime = null): bool
    {
        $code = preg_replace('/\s+/', '', $code) ?? '';
        if (! preg_match('/^\d{'.$this->digits.'}$/', $code)) {
            return false;
        }

        $now = $unixTime ?? time();
        $counter = intdiv($now, $this->periodSeconds);

        for ($i = -$window; $i <= $window; $i++) {
            $expected = $this->generate($secretBase32, $counter + $i);
            if (hash_equals($expected, $code)) {
                return true;
            }
        }

        return false;
    }

    /**
     * Generate a TOTP code for a given counter (time-step index).
     */
    public function generate(string $secretBase32, int $counter): string
    {
        $key = $this->base32Decode($secretBase32);

        // 8-byte big-endian counter
        $binCounter = pack('N2', ($counter >> 32) & 0xffffffff, $counter & 0xffffffff);

        $hmac = hash_hmac($this->algo, $binCounter, $key, true);
        $offset = ord($hmac[strlen($hmac) - 1]) & 0x0f;

        $part = substr($hmac, $offset, 4);
        if ($part === false || strlen($part) !== 4) {
            return str_repeat('0', $this->digits);
        }

        $value = unpack('N', $part)[1] & 0x7fffffff;
        $mod = 10 ** $this->digits;
        $otp = (string) ($value % $mod);

        return str_pad($otp, $this->digits, '0', STR_PAD_LEFT);
    }

    /**
     * Decode Base32 (RFC 4648) secret. Accepts lowercase, spaces, and padding.
     */
    private function base32Decode(string $b32): string
    {
        $b32 = strtoupper($b32);
        $b32 = preg_replace('/[^A-Z2-7=]/', '', $b32) ?? '';
        $b32 = rtrim($b32, '=');

        if ($b32 === '') {
            return '';
        }

        $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
        $buffer = 0;
        $bitsLeft = 0;
        $out = '';

        $len = strlen($b32);
        for ($i = 0; $i < $len; $i++) {
            $ch = $b32[$i];
            $val = strpos($alphabet, $ch);
            if ($val === false) {
                continue;
            }

            $buffer = ($buffer << 5) | $val;
            $bitsLeft += 5;

            if ($bitsLeft >= 8) {
                $bitsLeft -= 8;
                $byte = ($buffer >> $bitsLeft) & 0xff;
                $out .= chr($byte);
            }
        }

        return $out;
    }

    /**
     * Generate a new random Base32 secret (RFC 4648), suitable for Google Authenticator.
     */
    public function generateSecretBase32(int $bytes = 20): string
    {
        if ($bytes < 10) {
            $bytes = 10;
        }
        $raw = random_bytes($bytes);
        return $this->base32Encode($raw);
    }

    /**
     * Build an otpauth URI (QR payload) for authenticator apps.
     */
    public function buildOtpAuthUri(string $issuer, string $accountLabel, string $secretBase32): string
    {
        $issuer = trim($issuer);
        $accountLabel = trim($accountLabel);

        $label = rawurlencode($issuer.':'.$accountLabel);
        $qs = http_build_query([
            'secret' => $secretBase32,
            'issuer' => $issuer,
            'digits' => $this->digits,
            'period' => $this->periodSeconds,
            'algorithm' => strtoupper($this->algo),
        ], '', '&', PHP_QUERY_RFC3986);

        return 'otpauth://totp/'.$label.'?'.$qs;
    }

    private function base32Encode(string $raw): string
    {
        if ($raw === '') {
            return '';
        }

        $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
        $buffer = 0;
        $bitsLeft = 0;
        $out = '';

        $len = strlen($raw);
        for ($i = 0; $i < $len; $i++) {
            $buffer = ($buffer << 8) | ord($raw[$i]);
            $bitsLeft += 8;

            while ($bitsLeft >= 5) {
                $bitsLeft -= 5;
                $idx = ($buffer >> $bitsLeft) & 0x1f;
                $out .= $alphabet[$idx];
            }
        }

        if ($bitsLeft > 0) {
            $idx = ($buffer << (5 - $bitsLeft)) & 0x1f;
            $out .= $alphabet[$idx];
        }

        return $out;
    }
}
