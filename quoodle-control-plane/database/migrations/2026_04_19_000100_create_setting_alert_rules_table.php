<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('setting_alert_rules', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->string('name', 190);
            $table->text('condition');
            $table->string('severity', 32)->default('warning');
            $table->json('channels')->nullable();
            $table->boolean('enabled')->default(true);
            $table->foreignUlid('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignUlid('updated_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->index(['enabled', 'severity']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('setting_alert_rules');
    }
};