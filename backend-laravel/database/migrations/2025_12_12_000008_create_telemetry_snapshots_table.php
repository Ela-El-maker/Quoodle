<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('telemetry_snapshots', function (Blueprint $table) {
            $table->ulid('id')->primary();
            $table->string('device_id');
            $table->timestamp('timestamp');
            $table->json('metrics');
            $table->timestamps();
            $table->index('device_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('telemetry_snapshots');
    }
};
