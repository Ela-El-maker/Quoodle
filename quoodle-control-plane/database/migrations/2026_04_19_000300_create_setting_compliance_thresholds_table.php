<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('setting_compliance_thresholds', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->string('control', 190);
            $table->string('metric', 190);
            $table->decimal('threshold', 12, 4);
            $table->string('unit', 32)->nullable();
            $table->string('severity', 32)->default('warning');
            $table->boolean('enabled')->default(true);
            $table->foreignUlid('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignUlid('updated_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->index(['enabled', 'severity']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('setting_compliance_thresholds');
    }
};