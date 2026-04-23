<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::table('commands', function (Blueprint $table) {
            $table->string('origin_channel', 32)->nullable()->after('user_id');
            $table->string('origin_session_id', 64)->nullable()->after('origin_channel');
            $table->ulid('origin_mobile_device_id')->nullable()->after('origin_session_id');

            $table->index(['origin_channel', 'queued_at'], 'commands_origin_channel_queued_idx');
            $table->index('origin_mobile_device_id', 'commands_origin_mobile_device_idx');

            $table->foreign('origin_mobile_device_id', 'commands_origin_mobile_device_fk')
                ->references('id')
                ->on('mobile_devices')
                ->nullOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('commands', function (Blueprint $table) {
            $table->dropForeign('commands_origin_mobile_device_fk');
            $table->dropIndex('commands_origin_channel_queued_idx');
            $table->dropIndex('commands_origin_mobile_device_idx');
            $table->dropColumn([
                'origin_channel',
                'origin_session_id',
                'origin_mobile_device_id',
            ]);
        });
    }
};
