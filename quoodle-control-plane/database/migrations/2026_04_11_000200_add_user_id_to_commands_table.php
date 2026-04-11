<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        $driver = Schema::getConnection()->getDriverName();
        $database = Schema::getConnection()->getDatabaseName();

        $this->dropUserIdForeignAndIndex($database, $driver);

        if (Schema::hasColumn('commands', 'user_id')) {
            DB::statement('ALTER TABLE `commands` DROP COLUMN `user_id`');
        }

        if ($driver === 'sqlite') {
            DB::statement('ALTER TABLE `commands` ADD COLUMN `user_id` VARCHAR(64) NULL');
            return;
        }

        $userIdColumn = DB::selectOne(
            'SELECT COLUMN_TYPE, CHARACTER_SET_NAME, COLLATION_NAME
             FROM information_schema.COLUMNS
             WHERE TABLE_SCHEMA = ?
               AND TABLE_NAME = ?
               AND COLUMN_NAME = ?
             LIMIT 1',
            [$database, 'users', 'id']
        );

        $columnType = strtolower((string) ($userIdColumn->COLUMN_TYPE ?? 'char(26)'));
        $charset = (string) ($userIdColumn->CHARACTER_SET_NAME ?? '');
        $collation = (string) ($userIdColumn->COLLATION_NAME ?? '');
        $charsetClause = $this->isTextualColumnType($columnType) && $charset !== '' ? " CHARACTER SET {$charset}" : '';
        $collationClause = $this->isTextualColumnType($columnType) && $collation !== '' ? " COLLATE {$collation}" : '';

        DB::statement("ALTER TABLE `commands` ADD COLUMN `user_id` {$columnType}{$charsetClause}{$collationClause} NULL AFTER `device_id`");
        DB::statement('CREATE INDEX `commands_user_id_idx` ON `commands` (`user_id`)');
        DB::statement(
            'ALTER TABLE `commands` ADD CONSTRAINT `commands_user_id_fk`
             FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE SET NULL'
        );
    }

    public function down(): void
    {
        $driver = Schema::getConnection()->getDriverName();
        $database = Schema::getConnection()->getDatabaseName();

        $this->dropUserIdForeignAndIndex($database, $driver);

        if (Schema::hasColumn('commands', 'user_id')) {
            DB::statement('ALTER TABLE `commands` DROP COLUMN `user_id`');
        }
    }

    private function dropUserIdForeignAndIndex(string $database, string $driver): void
    {
        if ($driver === 'sqlite') {
            return;
        }

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
            DB::statement('ALTER TABLE `commands` DROP FOREIGN KEY `commands_user_id_fk`');
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
            DB::statement('DROP INDEX `commands_user_id_idx` ON `commands`');
        }
    }

    private function isTextualColumnType(string $columnType): bool
    {
        return str_contains($columnType, 'char') || str_contains($columnType, 'text');
    }
};
