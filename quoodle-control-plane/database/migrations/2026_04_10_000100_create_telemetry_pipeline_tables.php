<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('telemetry_events', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->string('device_id', 190)->index();
            $table->string('telemetry_scope', 64)->default('telemetry_extended');
            $table->string('schema_version', 32)->default('v1');
            $table->string('session_id', 190)->nullable();
            $table->unsignedBigInteger('seq')->nullable();
            $table->timestamp('timestamp')->index();
            $table->json('metrics');
            $table->json('masked_fields')->nullable();
            $table->string('policy_hash', 190)->nullable();
            $table->decimal('risk_score', 8, 2)->nullable();
            $table->string('presence_state', 32)->nullable();
            $table->string('connection_mode', 64)->nullable();
            $table->string('source', 64)->default('gateway');
            $table->timestamps();
        });

        Schema::create('device_telemetry_latest', function (Blueprint $table): void {
            $table->string('device_id', 190)->primary();
            $table->string('telemetry_scope', 64)->default('telemetry_extended');
            $table->string('schema_version', 32)->default('v1');
            $table->string('session_id', 190)->nullable();
            $table->unsignedBigInteger('seq')->nullable();
            $table->timestamp('timestamp')->nullable()->index();
            $table->json('metrics');
            $table->json('masked_fields')->nullable();
            $table->string('policy_hash', 190)->nullable();
            $table->decimal('risk_score', 8, 2)->nullable();
            $table->string('presence_state', 32)->nullable();
            $table->string('connection_mode', 64)->nullable();
            $table->timestamp('updated_at')->nullable();
        });

        Schema::create('telemetry_rollups', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->string('device_id', 190)->index();
            $table->timestamp('bucket_start')->index();
            $table->unsignedSmallInteger('bucket_minutes')->default(5);
            $table->unsignedInteger('samples')->default(0);
            $table->decimal('avg_cpu', 8, 2)->nullable();
            $table->decimal('avg_ram', 8, 2)->nullable();
            $table->decimal('avg_disk_usage', 8, 2)->nullable();
            $table->decimal('avg_network_tx', 12, 2)->nullable();
            $table->decimal('avg_network_rx', 12, 2)->nullable();
            $table->decimal('avg_risk_score', 8, 2)->nullable();
            $table->decimal('max_cpu', 8, 2)->nullable();
            $table->string('presence_state', 32)->nullable();
            $table->timestamps();
            $table->unique(['device_id', 'bucket_start', 'bucket_minutes'], 'telemetry_rollups_unique_bucket');
        });

        Schema::create('telemetry_ingest_errors', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->string('device_id', 190)->nullable()->index();
            $table->timestamp('timestamp')->index();
            $table->string('reason', 120);
            $table->json('details')->nullable();
            $table->string('source', 64)->default('gateway');
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('telemetry_ingest_errors');
        Schema::dropIfExists('telemetry_rollups');
        Schema::dropIfExists('device_telemetry_latest');
        Schema::dropIfExists('telemetry_events');
    }
};

