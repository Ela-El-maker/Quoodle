<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('ai_conversations', function (Blueprint $table): void {
            $table->string('id', 64)->primary();
            $table->string('tenant_id', 64)->default('default');
            $table->foreignUlid('actor_id')->constrained('users')->cascadeOnDelete();
            $table->string('surface', 128)->nullable();
            $table->string('title', 255)->nullable();
            $table->string('state', 32)->default('active');
            $table->string('latest_artifact_id', 26)->nullable();
            $table->timestamp('last_activity_at');
            $table->timestamps();

            $table->index(['tenant_id', 'actor_id', 'last_activity_at'], 'ai_conv_tenant_actor_activity_idx');
            $table->index(['tenant_id', 'state', 'last_activity_at'], 'ai_conv_tenant_state_activity_idx');
        });

        Schema::create('ai_messages', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->string('conversation_id', 64);
            $table->string('tenant_id', 64)->default('default');
            $table->string('role', 32);
            $table->json('content_json');
            $table->string('artifact_id', 26)->nullable();
            $table->timestamps();

            $table->foreign('conversation_id')->references('id')->on('ai_conversations')->cascadeOnDelete();
            $table->index(['conversation_id', 'created_at'], 'ai_msg_conversation_created_idx');
            $table->index(['tenant_id', 'created_at'], 'ai_msg_tenant_created_idx');
            $table->index('artifact_id', 'ai_msg_artifact_idx');
        });

        Schema::create('ai_artifacts', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->string('tenant_id', 64)->default('default');
            $table->string('conversation_id', 64);
            $table->foreignUlid('actor_id')->constrained('users')->cascadeOnDelete();
            $table->string('artifact_type', 64);
            $table->string('state', 32)->default('created');
            $table->string('subject_type', 32);
            $table->string('subject_id', 64);
            $table->decimal('confidence_score', 5, 4)->nullable();
            $table->unsignedSmallInteger('risk_score')->nullable();
            $table->string('title', 255)->nullable();
            $table->text('summary')->nullable();
            $table->json('payload_json');
            $table->string('prompt_hash', 128)->nullable();
            $table->string('tool_call_set_hash', 128)->nullable();
            $table->string('provider', 32)->nullable();
            $table->string('model', 64)->nullable();
            $table->timestamp('expires_at')->nullable();
            $table->timestamps();

            $table->foreign('conversation_id')->references('id')->on('ai_conversations')->cascadeOnDelete();
            $table->index(['tenant_id', 'artifact_type', 'created_at'], 'ai_art_tenant_type_created_idx');
            $table->index(['tenant_id', 'subject_type', 'subject_id', 'created_at'], 'ai_art_subject_lookup_idx');
            $table->index(['tenant_id', 'state', 'created_at'], 'ai_art_tenant_state_created_idx');
            $table->index(['conversation_id', 'created_at'], 'ai_art_conversation_created_idx');
        });

        Schema::create('ai_evidence_refs', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->foreignUlid('artifact_id')->constrained('ai_artifacts')->cascadeOnDelete();
            $table->string('tenant_id', 64)->default('default');
            $table->string('source_type', 64);
            $table->string('source_id', 128);
            $table->timestamp('source_ts')->nullable();
            $table->string('excerpt_summary', 512)->nullable();
            $table->string('excerpt_hash', 128)->nullable();
            $table->decimal('confidence_weight', 5, 4)->nullable();
            $table->integer('freshness_seconds')->nullable();
            $table->string('uri', 512)->nullable();
            $table->unsignedSmallInteger('rank')->default(1);
            $table->timestamps();

            $table->index(['artifact_id', 'rank'], 'ai_evidence_artifact_rank_idx');
            $table->index(['tenant_id', 'source_type', 'source_id'], 'ai_evidence_source_lookup_idx');
        });

        Schema::create('ai_tool_calls', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->string('tenant_id', 64)->default('default');
            $table->string('conversation_id', 64);
            $table->string('artifact_id', 26)->nullable();
            $table->string('tool_name', 64);
            $table->string('input_hash', 128)->nullable();
            $table->string('output_hash', 128)->nullable();
            $table->string('scope_hash', 128)->nullable();
            $table->integer('duration_ms')->default(0);
            $table->string('status', 32)->default('ok');
            $table->string('error_code', 64)->nullable();
            $table->integer('rows_returned')->nullable();
            $table->timestamps();

            $table->foreign('conversation_id')->references('id')->on('ai_conversations')->cascadeOnDelete();
            $table->index(['tenant_id', 'tool_name', 'created_at'], 'ai_tool_tenant_name_created_idx');
            $table->index('artifact_id', 'ai_tool_artifact_idx');
        });

        Schema::create('ai_model_calls', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->string('tenant_id', 64)->default('default');
            $table->string('conversation_id', 64);
            $table->string('artifact_id', 26)->nullable();
            $table->string('provider', 32)->nullable();
            $table->string('model', 64)->nullable();
            $table->string('api_mode', 32)->nullable();
            $table->string('provider_response_id', 128)->nullable();
            $table->string('request_hash', 128)->nullable();
            $table->string('tool_call_set_hash', 128)->nullable();
            $table->integer('input_tokens')->nullable();
            $table->integer('output_tokens')->nullable();
            $table->integer('latency_ms')->default(0);
            $table->string('status', 32)->default('ok');
            $table->string('error_code', 64)->nullable();
            $table->json('reasoning_summary_json')->nullable();
            $table->timestamps();

            $table->foreign('conversation_id')->references('id')->on('ai_conversations')->cascadeOnDelete();
            $table->index(['tenant_id', 'model', 'created_at'], 'ai_model_tenant_model_created_idx');
            $table->index('artifact_id', 'ai_model_artifact_idx');
        });

        Schema::create('ai_guardrail_events', function (Blueprint $table): void {
            $table->ulid('id')->primary();
            $table->string('tenant_id', 64)->default('default');
            $table->string('conversation_id', 64);
            $table->string('artifact_id', 26)->nullable();
            $table->string('event_type', 64);
            $table->string('severity', 16)->default('info');
            $table->json('detail_json');
            $table->timestamps();

            $table->foreign('conversation_id')->references('id')->on('ai_conversations')->cascadeOnDelete();
            $table->index(['tenant_id', 'event_type', 'created_at'], 'ai_guardrail_tenant_event_created_idx');
            $table->index('artifact_id', 'ai_guardrail_artifact_idx');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('ai_guardrail_events');
        Schema::dropIfExists('ai_model_calls');
        Schema::dropIfExists('ai_tool_calls');
        Schema::dropIfExists('ai_evidence_refs');
        Schema::dropIfExists('ai_artifacts');
        Schema::dropIfExists('ai_messages');
        Schema::dropIfExists('ai_conversations');
    }
};

