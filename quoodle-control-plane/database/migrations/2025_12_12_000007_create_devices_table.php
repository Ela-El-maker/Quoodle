<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('devices', function (Blueprint $table) {
            $table->string('device_id')->primary();
            $table->string('device_name')->nullable();
            $table->string('hwid')->nullable();
            $table->string('lifecycle_state')->default('pending_pairing');
            $table->timestamp('last_seen')->nullable();
            $table->string('agent_version')->nullable();
            $table->string('os_build')->nullable();
            $table->string('policy_hash')->nullable();
            $table->string('compliance_status')->default('unknown');
            $table->decimal('risk_score', 5, 2)->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('devices');
    }
};
