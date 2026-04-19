<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('setting_policy_entries', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->string('policy_key', 190)->unique();
            $table->text('policy_value')->nullable();
            $table->string('scope', 64)->default('global');
            $table->string('value_type', 32)->default('string');
            $table->text('description')->nullable();
            $table->boolean('is_mutable')->default(true);
            $table->foreignUlid('created_by')->nullable()->constrained('users')->nullOnDelete();
            $table->foreignUlid('updated_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->index(['scope', 'is_mutable']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('setting_policy_entries');
    }
};