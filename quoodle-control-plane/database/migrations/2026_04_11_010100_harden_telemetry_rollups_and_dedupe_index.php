<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        $driver = Schema::getConnection()->getDriverName();
        if ($driver !== 'mysql') {
            return;
        }

        $database = Schema::getConnection()->getDatabaseName();

        $dedupeIndexExists = DB::selectOne(
            'SELECT INDEX_NAME
             FROM information_schema.STATISTICS
             WHERE TABLE_SCHEMA = ?
               AND TABLE_NAME = ?
               AND INDEX_NAME = ?
             LIMIT 1',
            [$database, 'telemetry_events', 'telemetry_events_dedupe_lookup_idx']
        );

        if ($dedupeIndexExists === null) {
            DB::statement(
                'CREATE INDEX telemetry_events_dedupe_lookup_idx
                 ON telemetry_events (device_id, telemetry_scope, session_id, seq)'
            );
        }

        DB::statement('ALTER TABLE telemetry_rollups MODIFY avg_network_tx DECIMAL(20,4) NULL');
        DB::statement('ALTER TABLE telemetry_rollups MODIFY avg_network_rx DECIMAL(20,4) NULL');
    }

    public function down(): void
    {
        $driver = Schema::getConnection()->getDriverName();
        if ($driver !== 'mysql') {
            return;
        }

        $database = Schema::getConnection()->getDatabaseName();

        $dedupeIndexExists = DB::selectOne(
            'SELECT INDEX_NAME
             FROM information_schema.STATISTICS
             WHERE TABLE_SCHEMA = ?
               AND TABLE_NAME = ?
               AND INDEX_NAME = ?
             LIMIT 1',
            [$database, 'telemetry_events', 'telemetry_events_dedupe_lookup_idx']
        );

        if ($dedupeIndexExists !== null) {
            DB::statement('DROP INDEX telemetry_events_dedupe_lookup_idx ON telemetry_events');
        }

        DB::statement('ALTER TABLE telemetry_rollups MODIFY avg_network_tx DECIMAL(12,2) NULL');
        DB::statement('ALTER TABLE telemetry_rollups MODIFY avg_network_rx DECIMAL(12,2) NULL');
    }
};

