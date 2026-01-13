<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('device_updates', function (Blueprint $table) {
            $table->ulid('id')->primary();
            $table->string('device_id');
            $table->string('release_id');
            $table->string('version');
            $table->string('phase')->default('pending');
            $table->integer('progress_percent')->default(0);
            $table->string('progress_detail')->nullable();
            $table->integer('error_code')->nullable();
            $table->string('error_message')->nullable();
            $table->string('rollback_snapshot_id')->nullable();
            $table->timestamp('last_update_at')->nullable();
            $table->timestamps();
            $table->index(['device_id', 'release_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('device_updates');
    }
};
