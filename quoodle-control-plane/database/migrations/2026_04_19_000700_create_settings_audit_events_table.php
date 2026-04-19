<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('settings_audit_events', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->foreignUlid('actor_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('actor_email', 190)->nullable();
            $table->string('target_type', 128);
            $table->string('target_id', 190)->nullable();
            $table->string('operation', 64);
            $table->string('before_hash', 64)->nullable();
            $table->string('after_hash', 64)->nullable();
            $table->json('before_payload')->nullable();
            $table->json('after_payload')->nullable();
            $table->json('meta')->nullable();
            $table->timestamp('occurred_at');
            $table->timestamps();

            $table->index(['target_type', 'target_id']);
            $table->index(['actor_user_id', 'occurred_at']);
            $table->index('operation');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('settings_audit_events');
    }
};