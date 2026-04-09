<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('devices', function (Blueprint $table) {
            if (! Schema::hasColumn('devices', 'identity_version')) {
                $table->string('identity_version', 32)->nullable()->after('hwid_hash');
            }
            if (! Schema::hasColumn('devices', 'identity_components')) {
                $table->json('identity_components')->nullable()->after('identity_version');
            }
            if (! Schema::hasColumn('devices', 'machine_secret_hash')) {
                $table->string('machine_secret_hash', 128)->nullable()->after('identity_components');
            }
        });
    }

    public function down(): void
    {
        Schema::table('devices', function (Blueprint $table) {
            $columns = [];
            foreach (['identity_version', 'identity_components', 'machine_secret_hash'] as $col) {
                if (Schema::hasColumn('devices', $col)) {
                    $columns[] = $col;
                }
            }

            if (! empty($columns)) {
                $table->dropColumn($columns);
            }
        });
    }
};

