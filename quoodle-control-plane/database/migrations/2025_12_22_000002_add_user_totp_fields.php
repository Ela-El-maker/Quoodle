<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('users', function (Blueprint $table) {
            if (! Schema::hasColumn('users', 'two_factor_enabled')) {
                $table->boolean('two_factor_enabled')->default(false);
            }
            if (! Schema::hasColumn('users', 'two_factor_secret')) {
                // Stored encrypted via Eloquent cast.
                $table->text('two_factor_secret')->nullable();
            }
        });
    }

    public function down(): void
    {
        Schema::table('users', function (Blueprint $table) {
            $cols = [];
            if (Schema::hasColumn('users', 'two_factor_enabled')) {
                $cols[] = 'two_factor_enabled';
            }
            if (Schema::hasColumn('users', 'two_factor_secret')) {
                $cols[] = 'two_factor_secret';
            }
            if (! empty($cols)) {
                $table->dropColumn($cols);
            }
        });
    }
};
