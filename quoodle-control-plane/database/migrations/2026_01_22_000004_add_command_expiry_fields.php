<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('commands', function (Blueprint $table) {
            if (! Schema::hasColumn('commands', 'ttl_seconds')) {
                $table->integer('ttl_seconds')->nullable();
            }
            if (! Schema::hasColumn('commands', 'expires_at')) {
                $table->timestamp('expires_at')->nullable();
            }
        });
    }

    public function down(): void
    {
        Schema::table('commands', function (Blueprint $table) {
            $cols = [];
            foreach (['ttl_seconds', 'expires_at'] as $col) {
                if (Schema::hasColumn('commands', $col)) {
                    $cols[] = $col;
                }
            }
            if (! empty($cols)) {
                $table->dropColumn($cols);
            }
        });
    }
};
