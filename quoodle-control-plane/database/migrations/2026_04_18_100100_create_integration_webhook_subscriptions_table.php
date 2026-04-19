<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('integration_webhook_subscriptions', function (Blueprint $table): void {
            $table->id();
            $table->foreignUlid('endpoint_id')->constrained('integration_webhook_endpoints')->cascadeOnDelete();
            $table->string('event_type', 128);
            $table->timestamps();

            $table->unique(['endpoint_id', 'event_type'], 'webhook_subscriptions_endpoint_event_unique');
            $table->index('event_type', 'webhook_subscriptions_event_idx');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('integration_webhook_subscriptions');
    }
};
