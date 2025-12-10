<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('alerts', function (Blueprint $table) {
            $table->ulid('id')->primary();
            $table->string('alert_id')->unique();
            $table->string('device_id')->nullable();
            $table->string('severity');
            $table->string('category');
            $table->text('message');
            $table->timestamp('timestamp');
            $table->boolean('acknowledged')->default(false);
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('alerts');
    }
};
