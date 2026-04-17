<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('scheduled_jobs', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->foreignUlid('created_by_user_id')->nullable()->constrained('users')->nullOnDelete();
            $table->string('created_by_role', 32);
            $table->string('name', 190);
            $table->string('method', 190);
            $table->json('params')->nullable();
            $table->string('target_type', 32)->default('device');
            $table->json('target_ids')->nullable();
            $table->string('cron_expression', 128);
            $table->string('timezone', 64)->default('UTC');
            $table->boolean('enabled')->default(true);
            $table->timestamp('last_run_at')->nullable();
            $table->timestamp('next_run_at')->nullable()->index();
            $table->timestamps();

            $table->index(['enabled', 'next_run_at'], 'scheduled_jobs_enabled_next_run_idx');
        });

        Schema::create('scheduled_job_runs', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->foreignUlid('job_id')->constrained('scheduled_jobs')->cascadeOnDelete();
            $table->string('trigger', 32)->default('schedule');
            $table->timestamp('scheduled_for');
            $table->string('status', 32)->default('pending');
            $table->timestamp('started_at')->nullable();
            $table->timestamp('finished_at')->nullable();
            $table->unsignedInteger('total_targets')->default(0);
            $table->unsignedInteger('dispatched_count')->default(0);
            $table->unsignedInteger('failed_count')->default(0);
            $table->json('result_summary')->nullable();
            $table->text('error_message')->nullable();
            $table->timestamps();

            $table->unique(['job_id', 'scheduled_for'], 'scheduled_job_runs_job_scheduled_unique');
            $table->index(['status', 'started_at'], 'scheduled_job_runs_status_started_idx');
        });

        Schema::create('scheduled_job_run_items', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->foreignUlid('run_id')->constrained('scheduled_job_runs')->cascadeOnDelete();
            $table->string('device_id', 190);
            $table->foreignUlid('command_id')->nullable()->constrained('commands')->nullOnDelete();
            $table->string('status', 32)->default('pending');
            $table->text('error_message')->nullable();
            $table->json('result_summary')->nullable();
            $table->timestamp('started_at')->nullable();
            $table->timestamp('finished_at')->nullable();
            $table->timestamps();

            $table->unique(['run_id', 'device_id'], 'scheduled_job_run_items_run_device_unique');
            $table->index(['device_id', 'status'], 'scheduled_job_run_items_device_status_idx');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('scheduled_job_run_items');
        Schema::dropIfExists('scheduled_job_runs');
        Schema::dropIfExists('scheduled_jobs');
    }
};
