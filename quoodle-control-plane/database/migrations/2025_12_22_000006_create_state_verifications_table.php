<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('state_verifications', function (Blueprint $table) {
            $table->ulid('id')->primary();
            $table->string('device_id')->index();
            $table->foreignUlid('command_id')->nullable()->index()->constrained('commands')->nullOnDelete();
            $table->string('method')->nullable();
            $table->string('expected_policy_hash')->nullable();
            $table->timestamp('not_before')->index();
            $table->string('status')->default('pending'); // pending|ok|failed
            $table->text('details')->nullable();
            $table->timestamp('resolved_at')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('state_verifications');
    }
};
