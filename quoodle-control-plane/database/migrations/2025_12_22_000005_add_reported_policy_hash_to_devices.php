<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('devices', function (Blueprint $table) {
            if (! Schema::hasColumn('devices', 'reported_policy_hash')) {
                $table->string('reported_policy_hash')->nullable()->after('policy_hash');
            }
        });
    }

    public function down(): void
    {
        Schema::table('devices', function (Blueprint $table) {
            if (Schema::hasColumn('devices', 'reported_policy_hash')) {
                $table->dropColumn('reported_policy_hash');
            }
        });
    }
};
