<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        $driver = Schema::getConnection()->getDriverName();
        $database = Schema::getConnection()->getDatabaseName();

        if (Schema::hasColumn('commands', 'user_id')) {
            if ($driver !== 'sqlite') {
                $foreignExists = DB::selectOne(
                    'SELECT CONSTRAINT_NAME
                     FROM information_schema.KEY_COLUMN_USAGE
                     WHERE TABLE_SCHEMA = ?
                       AND TABLE_NAME = ?
                       AND CONSTRAINT_NAME = ?
                     LIMIT 1',
                    [$database, 'commands', 'commands_user_id_fk']
                );
                if ($foreignExists !== null) {
                    Schema::table('commands', function (Blueprint $table): void {
                        $table->dropForeign('commands_user_id_fk');
                    });
                }

                $indexExists = DB::selectOne(
                    'SELECT INDEX_NAME
                     FROM information_schema.STATISTICS
                     WHERE TABLE_SCHEMA = ?
                       AND TABLE_NAME = ?
                       AND INDEX_NAME = ?
                     LIMIT 1',
                    [$database, 'commands', 'commands_user_id_idx']
                );
                if ($indexExists !== null) {
                    Schema::table('commands', function (Blueprint $table): void {
                        $table->dropIndex('commands_user_id_idx');
                    });
                }
            }

            Schema::table('commands', function (Blueprint $table): void {
                $table->dropColumn('user_id');
            });
        }

        Schema::table('commands', function (Blueprint $table): void {
            if (! Schema::hasColumn('commands', 'user_id')) {
                $table->ulid('user_id')->nullable()->after('device_id');
                $table->index('user_id', 'commands_user_id_idx');
            }
        });

        if ($driver !== 'sqlite') {
            Schema::table('commands', function (Blueprint $table): void {
                $table->foreign('user_id', 'commands_user_id_fk')
                    ->references('id')
                    ->on('users')
                    ->nullOnDelete();
            });
        }
    }

    public function down(): void
    {
        $driver = Schema::getConnection()->getDriverName();
        $database = Schema::getConnection()->getDatabaseName();

        if (Schema::hasColumn('commands', 'user_id')) {
            if ($driver !== 'sqlite') {
                $foreignExists = DB::selectOne(
                    'SELECT CONSTRAINT_NAME
                     FROM information_schema.KEY_COLUMN_USAGE
                     WHERE TABLE_SCHEMA = ?
                       AND TABLE_NAME = ?
                       AND CONSTRAINT_NAME = ?
                     LIMIT 1',
                    [$database, 'commands', 'commands_user_id_fk']
                );
                if ($foreignExists !== null) {
                    Schema::table('commands', function (Blueprint $table): void {
                        $table->dropForeign('commands_user_id_fk');
                    });
                }

                $indexExists = DB::selectOne(
                    'SELECT INDEX_NAME
                     FROM information_schema.STATISTICS
                     WHERE TABLE_SCHEMA = ?
                       AND TABLE_NAME = ?
                       AND INDEX_NAME = ?
                     LIMIT 1',
                    [$database, 'commands', 'commands_user_id_idx']
                );
                if ($indexExists !== null) {
                    Schema::table('commands', function (Blueprint $table): void {
                        $table->dropIndex('commands_user_id_idx');
                    });
                }
            }

            Schema::table('commands', function (Blueprint $table): void {
                if (Schema::hasColumn('commands', 'user_id')) {
                    $table->dropColumn('user_id');
                }
            });
        }
    }
};
