<?php

namespace Tests\Feature;

use App\Models\Alert;
use App\Models\AuditTrail;
use App\Models\AuthToken;
use App\Models\Command;
use App\Models\Device;
use App\Models\DeviceTelemetryLatest;
use App\Models\User;
use App\Services\JWT\JWTSigner;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use PHPUnit\Framework\Attributes\RequiresPhpExtension;
use Tests\TestCase;

#[RequiresPhpExtension('pdo_sqlite')]
class ComplianceAuditActivationTest extends TestCase
{
    use RefreshDatabase;

    private function issueJwtFor(User $user): string
    {
        if (! file_exists(config('jwt.private_key_path')) || ! file_exists(config('jwt.public_key_path'))) {
            $this->markTestSkipped('JWT keys not configured. Run: php artisan jwt:generate-keys');
        }

        $sessionId = 'sess-'.uniqid();
        AuthToken::create([
            'user_id' => $user->id,
            'session_id' => $sessionId,
            'device_fingerprint' => 'test-device',
            'refresh_token_hash' => hash('sha256', 'test-refresh-'.$sessionId),
            'expires_at' => now()->addHour(),
        ]);

        return app(JWTSigner::class)->issueForUser($user, $sessionId);
    }

    private function createCommand(string $deviceId, ?string $userId, string $method, string $state, array $overrides = []): Command
    {
        return Command::create(array_merge([
            'client_message_id' => (string) Str::uuid(),
            'device_id' => $deviceId,
            'user_id' => $userId,
            'method' => $method,
            'params' => ['from' => 'test'],
            'sensitive' => false,
            'state' => $state,
            'status' => 'accepted',
            'trace_id' => (string) Str::uuid(),
            'queued_at' => now('UTC')->subMinute(),
            'dispatched_at' => now('UTC')->subSeconds(45),
            'completed_at' => now('UTC')->subSeconds(30),
            'execution_state' => $state,
        ], $overrides));
    }

    /** @test */
    public function audit_events_endpoint_returns_normalized_filtered_paginated_data(): void
    {
        $operator = User::factory()->create(['role' => User::ROLE_OPERATOR, 'email' => 'operator@quoodle.test']);
        $other = User::factory()->create(['role' => User::ROLE_OPERATOR, 'email' => 'other@quoodle.test']);

        Device::create([
            'device_id' => 'aud-own-001',
            'user_id' => $operator->id,
            'device_name' => 'Owned Device',
            'lifecycle_state' => 'online',
        ]);
        Device::create([
            'device_id' => 'aud-other-001',
            'user_id' => $other->id,
            'device_name' => 'Other Device',
            'lifecycle_state' => 'online',
        ]);

        $this->createCommand('aud-own-001', $operator->id, 'lock_screen', 'failed', [
            'error_message' => 'lock failed for test',
        ]);
        $this->createCommand('aud-own-001', $operator->id, 'ping', 'completed');
        $this->createCommand('aud-other-001', $other->id, 'lock_screen', 'failed', [
            'error_message' => 'should not be visible',
        ]);

        Alert::create([
            'alert_id' => 'ALT-OWN-1',
            'device_id' => 'aud-own-001',
            'severity' => 'critical',
            'category' => 'attestation',
            'message' => 'attestation check failed',
            'timestamp' => now('UTC')->subMinutes(2),
            'acknowledged' => false,
        ]);

        AuditTrail::create([
            'audit_id' => 'AUD-OWN-1',
            'actor' => 'operator@quoodle.test',
            'actor_id' => (string) $operator->id,
            'device_id' => 'aud-own-001',
            'event_type' => 'policy_change',
            'payload_hash' => hash('sha256', 'policy-change'),
            'prev_hash' => null,
            'hash' => hash('sha256', 'policy-change-hash'),
            'signature' => 'sig-policy',
            'timestamp' => now('UTC')->subMinutes(3),
        ]);

        $jwt = $this->issueJwtFor($operator);
        $headers = ['Authorization' => 'Bearer '.$jwt];

        $response = $this->withHeaders($headers)
            ->getJson('/api/audit/events?page=1&per_page=10&type=command_execution&outcome=failure&q=lock');

        $response->assertOk()->assertJsonStructure([
            'events' => [
                '*' => ['id', 'timestamp', 'actor', 'actor_role', 'event_type', 'action', 'target', 'detail', 'outcome', 'source'],
            ],
            'summary' => ['total_events', 'success_count', 'failure_count', 'active_actors'],
            'meta' => ['current_page', 'last_page', 'per_page', 'total'],
        ]);

        $events = collect($response->json('events'));
        $this->assertTrue($events->isNotEmpty());
        $this->assertTrue($events->every(fn (array $event): bool => $event['event_type'] === 'command_execution'));
        $this->assertTrue($events->every(fn (array $event): bool => $event['outcome'] === 'failure'));
        $this->assertTrue($events->every(fn (array $event): bool => str_contains(strtolower((string) $event['detail']), 'lock')));

        $allVisible = $this->withHeaders($headers)->getJson('/api/audit/events?page=1&per_page=200');
        $allVisible->assertOk();
        $targets = collect($allVisible->json('events'))->pluck('target');
        $this->assertFalse($targets->contains('aud-other-001'));
    }

    /** @test */
    public function compliance_overview_returns_fixed_controls_with_live_values(): void
    {
        $operator = User::factory()->create(['role' => User::ROLE_OPERATOR]);

        Device::create([
            'device_id' => 'cmp-dev-001',
            'user_id' => $operator->id,
            'device_name' => 'Device One',
            'lifecycle_state' => 'quarantined',
            'last_seen' => now('UTC')->subMinutes(5),
            'agent_version' => '0.0.0',
            'policy_hash' => 'policy-expected-1',
            'reported_policy_hash' => 'policy-old-1',
            'compliance_status' => 'non_compliant',
        ]);

        Device::create([
            'device_id' => 'cmp-dev-002',
            'user_id' => $operator->id,
            'device_name' => 'Device Two',
            'lifecycle_state' => 'online',
            'last_seen' => now('UTC')->subSeconds(15),
            'agent_version' => '0.0.2',
            'policy_hash' => 'policy-expected-2',
            'reported_policy_hash' => 'policy-expected-2',
            'compliance_status' => 'compliant',
        ]);

        DeviceTelemetryLatest::create([
            'device_id' => 'cmp-dev-001',
            'telemetry_scope' => 'telemetry_extended',
            'schema_version' => 'v1',
            'timestamp' => now('UTC')->subSeconds(30),
            'metrics' => [
                'kernel_guard' => false,
                'disk_encrypted' => false,
            ],
            'policy_hash' => 'policy-old-1',
            'updated_at' => now('UTC')->subSeconds(30),
        ]);
        DeviceTelemetryLatest::create([
            'device_id' => 'cmp-dev-002',
            'telemetry_scope' => 'telemetry_extended',
            'schema_version' => 'v1',
            'timestamp' => now('UTC')->subSeconds(30),
            'metrics' => [
                'kernel_guard' => true,
                'disk_encrypted' => true,
            ],
            'policy_hash' => 'policy-expected-2',
            'updated_at' => now('UTC')->subSeconds(30),
        ]);

        $this->createCommand('cmp-dev-001', $operator->id, 'collect_system_info', 'completed', [
            'request_sig' => null,
            'envelope_sig' => null,
        ]);
        $this->createCommand('cmp-dev-001', $operator->id, 'shutdown_device', 'completed', [
            'request_sig' => 'req-sig',
            'envelope_sig' => 'env-sig',
        ]);

        Alert::create([
            'alert_id' => 'ALT-CMP-1',
            'device_id' => 'cmp-dev-001',
            'severity' => 'critical',
            'category' => 'attestation',
            'message' => 'attestation mismatch detected',
            'timestamp' => now('UTC')->subMinutes(1),
            'acknowledged' => false,
        ]);

        $jwt = $this->issueJwtFor($operator);
        $response = $this->withHeaders(['Authorization' => 'Bearer '.$jwt])->getJson('/api/compliance/overview');

        $response->assertOk()->assertJsonStructure([
            'last_scan_at',
            'summary' => ['compliant', 'drift', 'non_compliant', 'pending', 'total', 'score'],
            'checks' => [
                '*' => ['id', 'category', 'control', 'description', 'status', 'affected_devices', 'last_checked', 'severity'],
            ],
        ]);

        $response->assertJsonPath('summary.total', 8);
        $response->assertJsonCount(8, 'checks');

        $checks = collect($response->json('checks'))->keyBy('id');
        $this->assertEqualsCanonicalizing(
            ['CC-001', 'CC-002', 'CC-003', 'CC-004', 'CC-005', 'CC-006', 'CC-007', 'CC-008'],
            $checks->keys()->all(),
        );

        $this->assertEquals('drift', $checks->get('CC-002')['status']);
        $this->assertEquals(1, $checks->get('CC-002')['affected_devices']);
        $this->assertEquals('non_compliant', $checks->get('CC-003')['status']);
        $this->assertEquals('non_compliant', $checks->get('CC-005')['status']);
        $this->assertEquals('non_compliant', $checks->get('CC-008')['status']);

        $score = (int) $response->json('summary.score');
        $this->assertGreaterThanOrEqual(0, $score);
        $this->assertLessThanOrEqual(100, $score);
        $this->assertNotEmpty((string) $response->json('last_scan_at'));
    }

    /** @test */
    public function compliance_audit_endpoint_returns_compliance_scoped_events(): void
    {
        $operator = User::factory()->create(['role' => User::ROLE_OPERATOR, 'email' => 'operator2@quoodle.test']);

        Device::create([
            'device_id' => 'cmp-aud-001',
            'user_id' => $operator->id,
            'device_name' => 'Compliance Audit Device',
            'lifecycle_state' => 'online',
        ]);

        $this->createCommand('cmp-aud-001', $operator->id, 'attestation_refresh', 'completed');
        $this->createCommand('cmp-aud-001', $operator->id, 'ping', 'completed');

        AuditTrail::create([
            'audit_id' => 'AUD-CMP-1',
            'actor' => 'operator2@quoodle.test',
            'actor_id' => (string) $operator->id,
            'device_id' => 'cmp-aud-001',
            'event_type' => 'policy_change',
            'payload_hash' => hash('sha256', 'policy-change-cmp'),
            'prev_hash' => null,
            'hash' => hash('sha256', 'policy-change-cmp-hash'),
            'signature' => 'sig-cmp',
            'timestamp' => now('UTC')->subSeconds(20),
        ]);

        $jwt = $this->issueJwtFor($operator);
        $response = $this->withHeaders(['Authorization' => 'Bearer '.$jwt])->getJson('/api/compliance/audit?page=1&per_page=50');

        $response->assertOk()->assertJsonStructure([
            'events' => [
                '*' => ['id', 'timestamp', 'actor', 'actor_role', 'event_type', 'action', 'target', 'detail', 'outcome', 'source'],
            ],
            'summary' => ['total_events', 'success_count', 'failure_count', 'active_actors'],
            'meta' => ['current_page', 'last_page', 'per_page', 'total'],
        ]);

        $events = collect($response->json('events'));
        $this->assertTrue($events->isNotEmpty());
        $this->assertTrue(
            $events->contains(fn (array $event): bool => $event['event_type'] === 'policy_change')
            || $events->contains(fn (array $event): bool => str_contains(strtolower((string) $event['detail']), 'attestation') || str_contains(strtolower((string) $event['action']), 'attestation'))
        );
        $this->assertFalse($events->contains(fn (array $event): bool => str_contains(strtolower((string) $event['detail']), 'ping')));
    }

    /** @test */
    public function export_endpoints_return_csv_content(): void
    {
        $operator = User::factory()->create(['role' => User::ROLE_OPERATOR]);

        Device::create([
            'device_id' => 'exp-dev-001',
            'user_id' => $operator->id,
            'device_name' => 'Export Device',
            'lifecycle_state' => 'online',
            'agent_version' => '0.0.2',
            'policy_hash' => 'policy-export',
            'reported_policy_hash' => 'policy-export',
            'compliance_status' => 'compliant',
        ]);

        DeviceTelemetryLatest::create([
            'device_id' => 'exp-dev-001',
            'telemetry_scope' => 'telemetry_extended',
            'schema_version' => 'v1',
            'timestamp' => now('UTC')->subSeconds(30),
            'metrics' => [
                'kernel_guard' => true,
                'disk_encrypted' => true,
            ],
            'policy_hash' => 'policy-export',
            'updated_at' => now('UTC')->subSeconds(30),
        ]);

        $this->createCommand('exp-dev-001', $operator->id, 'get_system_info', 'completed', [
            'request_sig' => 'req-sig-export',
            'envelope_sig' => 'env-sig-export',
        ]);

        $jwt = $this->issueJwtFor($operator);
        $headers = ['Authorization' => 'Bearer '.$jwt];

        $auditExport = $this->withHeaders($headers)->get('/api/audit/events/export?format=csv');
        $auditExport->assertOk();
        $auditExport->assertHeader('content-type', 'text/csv; charset=UTF-8');
        $this->assertStringContainsString('id,timestamp,actor', $auditExport->streamedContent());

        $complianceExport = $this->withHeaders($headers)->get('/api/compliance/export?format=csv');
        $complianceExport->assertOk();
        $complianceExport->assertHeader('content-type', 'text/csv; charset=UTF-8');
        $this->assertStringContainsString('id,category,control,description,status,affected_devices,last_checked,severity', $complianceExport->streamedContent());
        $this->assertStringContainsString('CC-001', $complianceExport->streamedContent());
    }
}
