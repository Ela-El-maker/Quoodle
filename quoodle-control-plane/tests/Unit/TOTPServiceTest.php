<?php

namespace Tests\Unit;

use App\Services\Security\TOTPService;
use PHPUnit\Framework\TestCase;

final class TOTPServiceTest extends TestCase
{
    /**
     * RFC 6238 test vector secret (ASCII "12345678901234567890") encoded as Base32.
     */
    private const SECRET_B32 = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';

    public function testGeneratesKnownCodeAtT59SixDigits(): void
    {
        $totp = new TOTPService(periodSeconds: 30, digits: 6, algo: 'sha1');
        $code = $totp->verify(self::SECRET_B32, '287082', window: 0, unixTime: 59);
        $this->assertTrue($code);
    }

    public function testRejectsInvalidCode(): void
    {
        $totp = new TOTPService(periodSeconds: 30, digits: 6, algo: 'sha1');
        $ok = $totp->verify(self::SECRET_B32, '000000', window: 0, unixTime: 59);
        $this->assertFalse($ok);
    }

    public function testWindowAllowsAdjacentStep(): void
    {
        $totp = new TOTPService(periodSeconds: 30, digits: 6, algo: 'sha1');

        // Generate exact code at time 60 (next counter) and verify at time 59 with window=1.
        $counterAt60 = intdiv(60, 30);
        $expectedAt60 = $totp->generate(self::SECRET_B32, $counterAt60);

        $ok = $totp->verify(self::SECRET_B32, $expectedAt60, window: 1, unixTime: 59);
        $this->assertTrue($ok);
    }

    public function testGeneratesBase32SecretAndOtpAuthUri(): void
    {
        $totp = new TOTPService(periodSeconds: 30, digits: 6, algo: 'sha1');
        $secret = $totp->generateSecretBase32();

        $this->assertMatchesRegularExpression('/^[A-Z2-7]+$/', $secret);
        $this->assertGreaterThanOrEqual(16, strlen($secret));

        $uri = $totp->buildOtpAuthUri('System002', 'user@example.com', $secret);
        $this->assertStringStartsWith('otpauth://totp/', $uri);
        $this->assertStringContainsString('secret='.$secret, $uri);
        $this->assertStringContainsString('issuer=System002', $uri);
    }
}
