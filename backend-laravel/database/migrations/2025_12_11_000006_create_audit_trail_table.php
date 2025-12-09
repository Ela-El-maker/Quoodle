<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('audit_trail', function (Blueprint $table) {
            $table->ulid('id')->primary();
            $table->string('audit_id');
            $table->string('actor');
            $table->string('actor_id');
            $table->string('device_id')->nullable();
            $table->string('event_type');
            $table->string('payload_hash');
            $table->string('prev_hash')->nullable();
            $table->string('hash');
            $table->string('signature')->nullable();
            $table->timestamp('timestamp');
            $table->timestamps();
            $table->index(['device_id', 'timestamp']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('audit_trail');
    }
};
