<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('commands', function (Blueprint $table) {
            if (! Schema::hasColumn('commands', 'execution_state')) {
                $table->string('execution_state')->default('queued');
            }
            if (! Schema::hasColumn('commands', 'result')) {
                $table->json('result')->nullable();
            }
            if (! Schema::hasColumn('commands', 'error_code')) {
                $table->integer('error_code')->nullable();
            }
            if (! Schema::hasColumn('commands', 'error_message')) {
                $table->string('error_message')->nullable();
            }
            if (! Schema::hasColumn('commands', 'completed_at')) {
                $table->timestamp('completed_at')->nullable();
            }
        });
    }

    public function down(): void
    {
        Schema::table('commands', function (Blueprint $table) {
            $table->dropColumn(['execution_state', 'result', 'error_code', 'error_message', 'completed_at']);
        });
    }
};
