<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('integration_webhook_deliveries', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->foreignUlid('endpoint_id')->constrained('integration_webhook_endpoints')->cascadeOnDelete();
            $table->string('event_type', 128)->index();
            $table->string('event_id', 64)->index();
            $table->json('payload_json');
            $table->unsignedSmallInteger('attempt')->default(0);
            $table->unsignedSmallInteger('max_attempts')->default(3);
            $table->string('status', 32)->default('pending')->index(); // pending|retrying|sent|dead_letter
            $table->timestamp('next_attempt_at')->nullable()->index();
            $table->unsignedSmallInteger('http_status')->nullable();
            $table->unsignedInteger('latency_ms')->nullable();
            $table->text('response_body')->nullable();
            $table->text('last_error')->nullable();
            $table->foreignUlid('replayed_from_delivery_id')->nullable()->constrained('integration_webhook_deliveries')->nullOnDelete();
            $table->timestamp('sent_at')->nullable();
            $table->timestamp('delivered_at')->nullable();
            $table->timestamps();

            $table->index(['endpoint_id', 'status', 'created_at'], 'webhook_deliveries_endpoint_status_created_idx');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('integration_webhook_deliveries');
    }
};
