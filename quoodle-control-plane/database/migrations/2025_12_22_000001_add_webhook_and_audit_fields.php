<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('devices', function (Blueprint $table) {
            if (! Schema::hasColumn('devices', 'hwid_hash')) {
                $table->string('hwid_hash')->nullable();
            }
            if (! Schema::hasColumn('devices', 'ed25519_pubkey_b64')) {
                $table->text('ed25519_pubkey_b64')->nullable();
            }
        });

        Schema::table('commands', function (Blueprint $table) {
            if (! Schema::hasColumn('commands', 'server_seq')) {
                $table->unsignedBigInteger('server_seq')->nullable();
            }
            if (! Schema::hasColumn('commands', 'envelope')) {
                $table->json('envelope')->nullable();
            }
            if (! Schema::hasColumn('commands', 'envelope_sig')) {
                $table->text('envelope_sig')->nullable();
            }
            if (! Schema::hasColumn('commands', 'request_sig')) {
                $table->text('request_sig')->nullable();
            }
        });
    }

    public function down(): void
    {
        Schema::table('devices', function (Blueprint $table) {
            $cols = [];
            if (Schema::hasColumn('devices', 'hwid_hash')) {
                $cols[] = 'hwid_hash';
            }
            if (Schema::hasColumn('devices', 'ed25519_pubkey_b64')) {
                $cols[] = 'ed25519_pubkey_b64';
            }
            if (! empty($cols)) {
                $table->dropColumn($cols);
            }
        });

        Schema::table('commands', function (Blueprint $table) {
            $cols = [];
            foreach (['server_seq', 'envelope', 'envelope_sig', 'request_sig'] as $c) {
                if (Schema::hasColumn('commands', $c)) {
                    $cols[] = $c;
                }
            }
            if (! empty($cols)) {
                $table->dropColumn($cols);
            }
        });
    }
};
