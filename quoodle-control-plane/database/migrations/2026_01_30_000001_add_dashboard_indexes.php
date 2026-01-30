<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('commands', function (Blueprint $table) {
            $table->index('created_at', 'commands_created_at_index');
        });

        Schema::table('alerts', function (Blueprint $table) {
            $table->index('created_at', 'alerts_created_at_index');
        });
    }

    public function down(): void
    {
        Schema::table('commands', function (Blueprint $table) {
            $table->dropIndex('commands_created_at_index');
        });

        Schema::table('alerts', function (Blueprint $table) {
            $table->dropIndex('alerts_created_at_index');
        });
    }
};
