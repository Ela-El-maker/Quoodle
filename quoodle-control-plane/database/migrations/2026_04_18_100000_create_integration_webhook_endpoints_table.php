<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('integration_webhook_endpoints', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->string('name', 190);
            $table->string('url', 2048);
            $table->string('status', 32)->default('active')->index(); // active|paused|failing
            $table->string('signing_algo', 32)->default('hmac-sha256');
            $table->string('retry_policy', 32)->default('exponential'); // exponential|linear|none
            $table->unsignedSmallInteger('max_retries')->default(3);
            $table->unsignedInteger('timeout_ms')->default(5000);
            $table->text('signing_secret_encrypted');
            $table->foreignUlid('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignUlid('updated_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->index(['created_by', 'status'], 'webhook_endpoints_owner_status_idx');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('integration_webhook_endpoints');
    }
};
