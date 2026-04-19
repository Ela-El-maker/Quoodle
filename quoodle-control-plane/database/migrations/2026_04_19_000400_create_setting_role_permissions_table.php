<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('setting_role_permissions', function (Blueprint $table): void {
            $table->id();
            $table->string('role', 32);
            $table->string('permission_key', 128);
            $table->boolean('allowed')->default(false);
            $table->foreignUlid('updated_by')->nullable()->constrained('users')->nullOnDelete();
            $table->timestamps();

            $table->unique(['role', 'permission_key']);
            $table->index(['role', 'allowed']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('setting_role_permissions');
    }
};