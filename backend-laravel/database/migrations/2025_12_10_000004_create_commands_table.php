<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    /**
     * Run the migrations.
     */
    public function up(): void
    {
        Schema::create('commands', function (Blueprint $table) {
            $table->ulid('id')->primary();
            $table->string('client_message_id');
            $table->string('device_id');
            $table->string('method');
            $table->json('params')->nullable();
            $table->boolean('sensitive')->default(false);
            $table->string('state')->default('queued');
            $table->string('status')->default('accepted');
            $table->string('reason')->nullable();
            $table->uuid('trace_id');
            $table->timestamp('queued_at')->nullable();
            $table->timestamp('dispatched_at')->nullable();
            $table->timestamps();
        });
    }

    /**
     * Reverse the migrations.
     */
    public function down(): void
    {
        Schema::dropIfExists('commands');
    }
};
