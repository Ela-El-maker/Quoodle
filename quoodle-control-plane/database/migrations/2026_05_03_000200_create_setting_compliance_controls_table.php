<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('setting_compliance_controls', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->string('check_id', 32)->unique();
            $table->string('evaluator', 64);
            $table->string('category', 190);
            $table->string('control', 190);
            $table->text('description');
            $table->string('severity', 32)->default('warning');
            $table->string('failure_status', 32)->default('non_compliant');
            $table->boolean('enabled')->default(true);
            $table->unsignedSmallInteger('sort_order')->default(100);
            $table->foreignUlid('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignUlid('updated_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->index(['enabled', 'sort_order']);
            $table->index('evaluator');
        });

        $now = now('UTC');
        DB::table('setting_compliance_controls')->insert([
            [
                'id' => (string) str()->ulid(),
                'check_id' => 'CC-001',
                'evaluator' => 'attestation_boot',
                'category' => 'Attestation',
                'control' => 'TPM-ATTEST-01',
                'description' => 'All devices must pass TPM attestation on boot',
                'severity' => 'critical',
                'failure_status' => 'non_compliant',
                'enabled' => true,
                'sort_order' => 10,
                'created_at' => $now,
                'updated_at' => $now,
            ],
            [
                'id' => (string) str()->ulid(),
                'check_id' => 'CC-002',
                'evaluator' => 'policy_hash_sync',
                'category' => 'Policy Sync',
                'control' => 'POL-SYNC-01',
                'description' => 'Device policy hash must match fleet policy-2026-04',
                'severity' => 'warning',
                'failure_status' => 'drift',
                'enabled' => true,
                'sort_order' => 20,
                'created_at' => $now,
                'updated_at' => $now,
            ],
            [
                'id' => (string) str()->ulid(),
                'check_id' => 'CC-003',
                'evaluator' => 'kernel_guard_active',
                'category' => 'Kernel Guard',
                'control' => 'KG-DRIVER-01',
                'description' => 'Kernel Guard driver must be active on all managed devices',
                'severity' => 'critical',
                'failure_status' => 'non_compliant',
                'enabled' => true,
                'sort_order' => 30,
                'created_at' => $now,
                'updated_at' => $now,
            ],
            [
                'id' => (string) str()->ulid(),
                'check_id' => 'CC-004',
                'evaluator' => 'agent_version_minimum',
                'category' => 'Agent Version',
                'control' => 'AGENT-VER-01',
                'description' => 'All agents must run version 0.0.1 or higher',
                'severity' => 'info',
                'failure_status' => 'non_compliant',
                'enabled' => true,
                'sort_order' => 40,
                'created_at' => $now,
                'updated_at' => $now,
            ],
            [
                'id' => (string) str()->ulid(),
                'check_id' => 'CC-005',
                'evaluator' => 'disk_encryption_enabled',
                'category' => 'Encryption',
                'control' => 'ENC-DISK-01',
                'description' => 'Full disk encryption must be enabled on all endpoints',
                'severity' => 'info',
                'failure_status' => 'non_compliant',
                'enabled' => true,
                'sort_order' => 50,
                'created_at' => $now,
                'updated_at' => $now,
            ],
            [
                'id' => (string) str()->ulid(),
                'check_id' => 'CC-006',
                'evaluator' => 'command_auth_integrity',
                'category' => 'Command Auth',
                'control' => 'CMD-AUTH-01',
                'description' => 'All commands must be Ed25519 signed and 2FA verified',
                'severity' => 'info',
                'failure_status' => 'non_compliant',
                'enabled' => true,
                'sort_order' => 60,
                'created_at' => $now,
                'updated_at' => $now,
            ],
            [
                'id' => (string) str()->ulid(),
                'check_id' => 'CC-007',
                'evaluator' => 'heartbeat_freshness',
                'category' => 'Heartbeat',
                'control' => 'HB-INTERVAL-01',
                'description' => 'Device heartbeat interval must not exceed 60 seconds',
                'severity' => 'warning',
                'failure_status' => 'drift',
                'enabled' => true,
                'sort_order' => 70,
                'created_at' => $now,
                'updated_at' => $now,
            ],
            [
                'id' => (string) str()->ulid(),
                'check_id' => 'CC-008',
                'evaluator' => 'quarantine_enforcement',
                'category' => 'Quarantine',
                'control' => 'QUAR-POLICY-01',
                'description' => 'Quarantined devices must block all non-remediation commands',
                'severity' => 'info',
                'failure_status' => 'non_compliant',
                'enabled' => true,
                'sort_order' => 80,
                'created_at' => $now,
                'updated_at' => $now,
            ],
        ]);
    }

    public function down(): void
    {
        Schema::dropIfExists('setting_compliance_controls');
    }
};
