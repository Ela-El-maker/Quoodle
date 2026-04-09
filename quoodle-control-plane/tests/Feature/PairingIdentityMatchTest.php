<?php

namespace Tests\Feature;

use App\Models\Device;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PHPUnit\Framework\Attributes\RequiresPhpExtension;
use Tests\TestCase;

#[RequiresPhpExtension('pdo_sqlite')]
class PairingIdentityMatchTest extends TestCase
{
    use RefreshDatabase;

    private const PUBKEY = 'dGVzdF9wdWJrZXlfYmFzZTY0';

    protected function setUp(): void
    {
        parent::setUp();
        config()->set('policy.master_hash', 'sha256:test-policy');
    }

    /** @test */
    public function pair_request_reuses_existing_device_on_unique_fuzzy_identity_match(): void
    {
        $owner = User::factory()->create();

        $existing = Device::create([
            'device_id' => 'dev-fuzzy-existing',
            'user_id' => $owner->id,
            'device_name' => 'Existing Device',
            'hwid' => 'old-fingerprint',
            'identity_version' => 'v1',
            'identity_components' => [
                'mb_uuid' => 'mb-anchor-hash',
                'cpu_id' => 'cpu-hash-1',
                'disk_serial' => 'disk-hash-1',
                'primary_mac' => 'mac-hash-1',
            ],
            'ed25519_pubkey_b64' => self::PUBKEY,
            'lifecycle_state' => 'online',
        ]);

        $response = $this->postJson('/api/pair/request', [
            'device_name' => 'New Label',
            'hwid' => 'new-fingerprint-v1',
            'pubkey' => self::PUBKEY,
            'identity_version' => 'v1',
            'identity_components' => [
                'mb_uuid' => 'mb-anchor-hash',
                'cpu_id' => 'cpu-hash-1',
                'disk_serial' => 'disk-hash-1',
                'primary_mac' => 'different-mac',
            ],
            'machine_secret_hash' => 'machine-secret-hash',
        ]);

        $response->assertOk();
        $response->assertJsonPath('device_id', $existing->device_id);

        $existing->refresh();
        $this->assertSame('new-fingerprint-v1', $existing->hwid);
        $this->assertSame('v1', $existing->identity_version);
    }

    /** @test */
    public function pair_request_returns_conflict_when_fuzzy_match_is_ambiguous(): void
    {
        Device::create([
            'device_id' => 'dev-amb-1',
            'device_name' => 'Ambiguous One',
            'hwid' => 'amb-hwid-1',
            'identity_version' => 'v1',
            'identity_components' => [
                'mb_uuid' => 'anchor',
                'cpu_id' => 'cpu-a',
                'disk_serial' => 'disk-a',
                'primary_mac' => 'mac-1',
            ],
            'ed25519_pubkey_b64' => self::PUBKEY,
            'lifecycle_state' => 'pending_pairing',
        ]);

        Device::create([
            'device_id' => 'dev-amb-2',
            'device_name' => 'Ambiguous Two',
            'hwid' => 'amb-hwid-2',
            'identity_version' => 'v1',
            'identity_components' => [
                'mb_uuid' => 'anchor',
                'cpu_id' => 'cpu-a',
                'disk_serial' => 'disk-b',
                'primary_mac' => 'mac-a',
            ],
            'ed25519_pubkey_b64' => self::PUBKEY,
            'lifecycle_state' => 'pending_pairing',
        ]);

        $response = $this->postJson('/api/pair/request', [
            'device_name' => 'Ambiguous Incoming',
            'hwid' => 'amb-hwid-new',
            'pubkey' => self::PUBKEY,
            'identity_version' => 'v1',
            'identity_components' => [
                'mb_uuid' => 'anchor',
                'cpu_id' => 'cpu-a',
                'disk_serial' => 'disk-a',
                'primary_mac' => 'mac-a',
            ],
        ]);

        $response->assertStatus(409);
        $response->assertJsonPath('reason', 'identity_match_ambiguous');
    }
}

