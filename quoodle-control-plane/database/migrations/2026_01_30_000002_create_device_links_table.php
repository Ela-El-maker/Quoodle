<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('device_links', function (Blueprint $table) {
            $table->ulid('id')->primary();
            $table->foreignUlid('user_id')->constrained()->cascadeOnDelete();
            $table->foreignUlid('mobile_device_id')->constrained('mobile_devices')->cascadeOnDelete();
            $table->string('device_id');
            $table->string('linked_via')->default('pair_confirm');
            $table->timestamp('linked_at')->nullable();
            $table->timestamps();

            $table->foreign('device_id')->references('device_id')->on('devices')->cascadeOnDelete();
            $table->unique(['mobile_device_id', 'device_id'], 'device_links_mobile_device_unique');
            $table->index(['user_id', 'device_id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('device_links');
    }
};
