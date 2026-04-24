<?php

namespace App\Services\AI;

use App\Models\AiArtifact;
use App\Models\AiConversation;
use App\Models\AiEvidenceRef;
use App\Models\AiGuardrailEvent;
use App\Models\AiMessage;
use App\Models\AiModelCall;
use App\Models\AiToolCall;
use App\Models\AuditTrail;
use App\Models\Command;
use App\Models\Device;
use App\Models\DeviceTelemetryLatest;
use App\Models\User;
use App\Services\Devices\DeviceVisibilityService;
use App\Services\SystemHealth\SystemHealthService;
use Illuminate\Auth\Access\AuthorizationException;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use RuntimeException;

class DeviceHealthCopilotService
{
    public function __construct(
        private readonly AiSidecarClient $sidecarClient,
        private readonly DeviceVisibilityService $visibility,
        private readonly SystemHealthService $systemHealthService,
    ) {
    }

    /**
     * @param  array<string, mixed>  $input
     * @return array<string, mixed>
     */
    public function ask(User $user, array $input, string $correlationId): array
    {
        if (! (bool) config('ai.global_enabled', false) || ! (bool) config('ai.device_copilot_enabled', false)) {
            throw new RuntimeException('ai_disabled');
        }

        $query = trim((string) ($input['query'] ?? ''));
        $deviceId = trim((string) (($input['selected_refs']['device_id'] ?? '')));
        $uiSurface = isset($input['ui_surface']) ? trim((string) $input['ui_surface']) : null;
        $tenantId = (string) config('ai.default_tenant_id', 'default');

        if ($query === '' || $deviceId === '') {
            throw new RuntimeException('invalid_request');
        }

        if (! $this->visibility->canViewDevice($user, $deviceId)) {
            throw new AuthorizationException('forbidden_device_scope');
        }

        $conversationId = $this->normalizeConversationId($input['conversation_id'] ?? null);
        $conversation = $this->resolveConversation(
            actor: $user,
            tenantId: $tenantId,
            conversationId: $conversationId,
            uiSurface: $uiSurface,
        );

        AiMessage::create([
            'conversation_id' => $conversation->id,
            'tenant_id' => $tenantId,
            'role' => 'user',
            'content_json' => [
                'query' => $query,
                'selected_refs' => ['device_id' => $deviceId],
                'ui_surface' => $uiSurface,
            ],
        ]);

        $contextBundle = $this->buildContextBundle($deviceId);
        $sidecarRequest = [
            'conversation_id' => $conversation->id,
            'query' => $query,
            'actor_context' => [
                'tenant_id' => $tenantId,
                'actor_id' => (string) $user->id,
                'role' => (string) $user->role,
                'session_id' => null,
            ],
            'scope_context' => [
                'allowed_device_ids' => [$deviceId],
                'allowed_actions' => [
                    'read_device_state',
                    'read_telemetry',
                    'read_command_failures',
                    'read_audit_events',
                    'read_system_health',
                ],
            ],
            'selected_refs' => ['device_id' => $deviceId],
            'ui_surface' => $uiSurface ?? 'web.device_detail',
            'correlation_id' => $correlationId,
            'context' => $contextBundle,
        ];

        try {
            $sidecarResponse = $this->sidecarClient->ask($sidecarRequest, $correlationId);
        } catch (RuntimeException $e) {
            AiModelCall::create([
                'tenant_id' => $tenantId,
                'conversation_id' => $conversation->id,
                'provider' => 'sidecar',
                'model' => 'internal',
                'api_mode' => 'http',
                'status' => 'error',
                'error_code' => $e->getMessage(),
                'latency_ms' => 0,
            ]);

            throw $e;
        }

        return DB::transaction(function () use (
            $conversation,
            $contextBundle,
            $correlationId,
            $deviceId,
            $query,
            $sidecarResponse,
            $tenantId,
            $uiSurface,
            $user,
        ): array {
            $artifactPayload = is_array($sidecarResponse['artifact'] ?? null) ? $sidecarResponse['artifact'] : [];
            $assistantMessage = trim((string) ($sidecarResponse['assistant_message'] ?? ''));
            $confidence = is_array($sidecarResponse['confidence'] ?? null) ? $sidecarResponse['confidence'] : [];
            $modelCall = is_array($sidecarResponse['model_call'] ?? null) ? $sidecarResponse['model_call'] : [];
            $freshnessSeconds = $this->safeInt($sidecarResponse['freshness_seconds'] ?? null);
            $toolCalls = is_array($sidecarResponse['tool_calls'] ?? null) ? $sidecarResponse['tool_calls'] : [];
            $evidenceRefs = is_array($sidecarResponse['evidence_refs'] ?? null) ? $sidecarResponse['evidence_refs'] : [];
            $guardrailEvents = is_array($sidecarResponse['guardrail_events'] ?? null) ? $sidecarResponse['guardrail_events'] : [];

            $artifact = AiArtifact::create([
                'tenant_id' => $tenantId,
                'conversation_id' => $conversation->id,
                'actor_id' => $user->id,
                'artifact_type' => (string) ($artifactPayload['artifact_type'] ?? 'answer'),
                'state' => (string) ($artifactPayload['state'] ?? 'created'),
                'subject_type' => 'device',
                'subject_id' => $deviceId,
                'confidence_score' => $this->safeFloat($confidence['score'] ?? null),
                'risk_score' => null,
                'title' => 'Device Health Copilot',
                'summary' => $assistantMessage !== '' ? $assistantMessage : (string) ($artifactPayload['summary'] ?? ''),
                'payload_json' => [
                    'status' => $sidecarResponse['status'] ?? 'ok',
                    'assistant_message' => $assistantMessage,
                    'artifact' => $artifactPayload,
                    'confidence' => $confidence,
                    'freshness_seconds' => $freshnessSeconds,
                    'query' => $query,
                    'ui_surface' => $uiSurface,
                    'selected_refs' => ['device_id' => $deviceId],
                    'context_summary' => [
                        'device_id' => $contextBundle['device_summary']['device_id'] ?? $deviceId,
                        'command_failures_count' => count($contextBundle['command_failures'] ?? []),
                        'audit_events_count' => count($contextBundle['audit_events'] ?? []),
                    ],
                ],
                'prompt_hash' => (string) ($artifactPayload['prompt_hash'] ?? ''),
                'tool_call_set_hash' => (string) ($artifactPayload['tool_call_set_hash'] ?? ''),
                'provider' => $this->nullableString($modelCall['provider'] ?? null),
                'model' => $this->nullableString($modelCall['model'] ?? null),
            ]);

            $rank = 1;
            foreach ($evidenceRefs as $evidenceRef) {
                if (! is_array($evidenceRef)) {
                    continue;
                }

                AiEvidenceRef::create([
                    'artifact_id' => $artifact->id,
                    'tenant_id' => $tenantId,
                    'source_type' => (string) ($evidenceRef['source_type'] ?? 'unknown'),
                    'source_id' => (string) ($evidenceRef['source_id'] ?? 'unknown'),
                    'source_ts' => $this->parseIsoTimestamp($evidenceRef['source_timestamp'] ?? null),
                    'excerpt_summary' => $this->nullableString($evidenceRef['excerpt_summary'] ?? null),
                    'excerpt_hash' => $this->nullableString($evidenceRef['excerpt_hash'] ?? null),
                    'confidence_weight' => $this->safeFloat($evidenceRef['confidence_weight'] ?? null),
                    'freshness_seconds' => $this->safeInt($evidenceRef['freshness_seconds'] ?? null),
                    'uri' => $this->nullableString($evidenceRef['uri'] ?? null),
                    'rank' => $rank++,
                ]);
            }

            foreach ($toolCalls as $toolCall) {
                if (! is_array($toolCall)) {
                    continue;
                }

                AiToolCall::create([
                    'tenant_id' => $tenantId,
                    'conversation_id' => $conversation->id,
                    'artifact_id' => $artifact->id,
                    'tool_name' => (string) ($toolCall['tool_name'] ?? 'unknown'),
                    'input_hash' => $this->nullableString($toolCall['input_hash'] ?? null),
                    'output_hash' => $this->nullableString($toolCall['output_hash'] ?? null),
                    'scope_hash' => $this->nullableString($toolCall['scope_hash'] ?? null),
                    'duration_ms' => $this->safeInt($toolCall['duration_ms'] ?? null) ?? 0,
                    'status' => (string) ($toolCall['status'] ?? 'error'),
                    'error_code' => $this->nullableString($toolCall['error_code'] ?? null),
                    'rows_returned' => $this->safeInt($toolCall['rows_returned'] ?? null),
                ]);
            }

            AiModelCall::create([
                'tenant_id' => $tenantId,
                'conversation_id' => $conversation->id,
                'artifact_id' => $artifact->id,
                'provider' => $this->nullableString($modelCall['provider'] ?? null),
                'model' => $this->nullableString($modelCall['model'] ?? null),
                'api_mode' => $this->nullableString($modelCall['api_mode'] ?? null),
                'provider_response_id' => $this->nullableString($modelCall['provider_response_id'] ?? null),
                'request_hash' => $this->nullableString($modelCall['request_hash'] ?? null),
                'tool_call_set_hash' => $this->nullableString($modelCall['tool_call_set_hash'] ?? null),
                'input_tokens' => $this->safeInt($modelCall['input_tokens'] ?? null),
                'output_tokens' => $this->safeInt($modelCall['output_tokens'] ?? null),
                'latency_ms' => $this->safeInt($modelCall['latency_ms'] ?? null) ?? 0,
                'status' => (string) ($modelCall['status'] ?? 'error'),
                'error_code' => $this->nullableString($modelCall['error_code'] ?? null),
                'reasoning_summary_json' => [
                    'prompt_id' => $this->nullableString($modelCall['prompt_id'] ?? null),
                    'prompt_version' => $this->nullableString($modelCall['prompt_version'] ?? null),
                    'prompt_source' => $this->nullableString($modelCall['prompt_source'] ?? null),
                    'prompt_hash' => $this->nullableString($modelCall['prompt_hash'] ?? null),
                ],
            ]);

            foreach ($guardrailEvents as $event) {
                if (! is_array($event)) {
                    continue;
                }

                AiGuardrailEvent::create([
                    'tenant_id' => $tenantId,
                    'conversation_id' => $conversation->id,
                    'artifact_id' => $artifact->id,
                    'event_type' => (string) ($event['event_type'] ?? 'guardrail.unknown'),
                    'severity' => (string) ($event['severity'] ?? 'info'),
                    'detail_json' => is_array($event['detail'] ?? null) ? $event['detail'] : [],
                ]);
            }

            AiMessage::create([
                'conversation_id' => $conversation->id,
                'tenant_id' => $tenantId,
                'role' => 'assistant',
                'content_json' => [
                    'message' => $assistantMessage,
                    'confidence' => $confidence,
                    'freshness_seconds' => $freshnessSeconds,
                    'artifact_id' => $artifact->id,
                ],
                'artifact_id' => $artifact->id,
            ]);

            $conversation->forceFill([
                'latest_artifact_id' => $artifact->id,
                'last_activity_at' => now(),
            ])->save();

            $this->writeAuditLink($user, $deviceId, $artifact->id, $correlationId);

            $evidenceProjection = $artifact->evidenceRefs()
                ->orderBy('rank')
                ->get()
                ->map(function (AiEvidenceRef $row): array {
                    return [
                        'source_type' => $row->source_type,
                        'source_id' => $row->source_id,
                        'excerpt_summary' => $row->excerpt_summary,
                        'freshness_seconds' => $row->freshness_seconds,
                        'rank' => $row->rank,
                        'uri' => $row->uri,
                    ];
                })
                ->values()
                ->all();

            return [
                'status' => (string) ($sidecarResponse['status'] ?? 'ok'),
                'conversation_id' => $conversation->id,
                'correlation_id' => $correlationId,
                'artifact' => [
                    'artifact_id' => $artifact->id,
                    'artifact_type' => $artifact->artifact_type,
                    'state' => $artifact->state,
                    'summary' => $artifact->summary,
                    'freshness_seconds' => $freshnessSeconds,
                    'created_at' => optional($artifact->created_at)?->toIso8601String(),
                ],
                'display' => [
                    'answer_text' => $assistantMessage,
                    'confidence' => [
                        'score' => $this->safeFloat($confidence['score'] ?? null),
                        'band' => $this->nullableString($confidence['band'] ?? null),
                    ],
                    'freshness_seconds' => $freshnessSeconds,
                    'evidence_refs' => $evidenceProjection,
                    'missing_information' => $this->safeStringArray(
                        $artifactPayload['missing_information']
                            ?? ($artifactPayload['missing_data'] ?? []),
                    ),
                    'suggested_prompts' => $this->safeStringArray(
                        $artifactPayload['next_safe_questions']
                            ?? ($artifactPayload['suggested_prompts'] ?? []),
                    ),
                ],
            ];
        });
    }

    /**
     * @return array<string, mixed>
     */
    public function getConversation(User $user, string $conversationId): array
    {
        $tenantId = (string) config('ai.default_tenant_id', 'default');
        $conversation = AiConversation::query()->find($conversationId);
        if (! $conversation) {
            throw new RuntimeException('conversation_not_found');
        }
        if ($conversation->actor_id !== $user->id || $conversation->tenant_id !== $tenantId) {
            throw new AuthorizationException('forbidden_conversation_scope');
        }

        $messages = AiMessage::query()
            ->where('conversation_id', $conversation->id)
            ->orderBy('created_at')
            ->get();
        $artifactIds = $messages
            ->pluck('artifact_id')
            ->filter(fn ($id) => is_string($id) && trim($id) !== '')
            ->values()
            ->all();

        $artifacts = AiArtifact::query()
            ->whereIn('id', $artifactIds)
            ->with(['evidenceRefs' => fn ($q) => $q->orderBy('rank')])
            ->get()
            ->keyBy('id');

        $transcript = [];
        foreach ($messages as $message) {
            $content = is_array($message->content_json) ? $message->content_json : [];
            $createdAt = optional($message->created_at)?->toIso8601String();

            if ($message->role === 'user') {
                $text = trim((string) ($content['query'] ?? ($content['message'] ?? '')));
                $transcript[] = [
                    'id' => 'msg_'.$message->id,
                    'type' => 'user_message',
                    'timestamp' => $createdAt,
                    'text' => $text,
                ];
                continue;
            }

            $hasArtifact = is_string($message->artifact_id) && trim($message->artifact_id) !== '';

            if ($message->role === 'assistant') {
                $text = trim((string) ($content['message'] ?? ''));
                // Avoid duplicating answer content in transcript when a canonical artifact
                // exists for this assistant turn. The artifact card is the primary UI object.
                if (! $hasArtifact) {
                    $transcript[] = [
                        'id' => 'msg_'.$message->id,
                        'type' => 'assistant_answer',
                        'timestamp' => $createdAt,
                        'text' => $text,
                    ];
                }
            } else {
                $transcript[] = [
                    'id' => 'msg_'.$message->id,
                    'type' => 'system_status',
                    'timestamp' => $createdAt,
                    'text' => trim((string) ($content['message'] ?? $message->role)),
                ];
            }

            if (! $hasArtifact) {
                continue;
            }
            $artifact = $artifacts->get($message->artifact_id);
            if (! $artifact) {
                continue;
            }

            $payload = is_array($artifact->payload_json) ? $artifact->payload_json : [];
            $assistant = is_array($payload['artifact'] ?? null) ? $payload['artifact'] : [];
            $confidence = is_array($payload['confidence'] ?? null) ? $payload['confidence'] : [];
            $missingInformation = $this->safeStringArray(
                $assistant['missing_information']
                    ?? ($payload['missing_information'] ?? []),
            );
            $suggestedPrompts = $this->safeStringArray(
                $assistant['next_safe_questions']
                    ?? ($assistant['suggested_prompts'] ?? []),
            );

            $evidenceRefs = $artifact->evidenceRefs->map(function (AiEvidenceRef $row): array {
                return [
                    'source_type' => $row->source_type,
                    'source_id' => $row->source_id,
                    'excerpt_summary' => $row->excerpt_summary,
                    'freshness_seconds' => $row->freshness_seconds,
                    'rank' => $row->rank,
                    'uri' => $row->uri,
                ];
            })->values()->all();

            $transcript[] = [
                'id' => 'art_'.$artifact->id,
                'type' => 'answer_artifact',
                'timestamp' => optional($artifact->created_at)?->toIso8601String(),
                'artifact' => [
                    'artifact_id' => $artifact->id,
                    'artifact_type' => $artifact->artifact_type,
                    'state' => $artifact->state,
                    'answer_text' => trim((string) ($payload['assistant_message'] ?? ($artifact->summary ?? ''))),
                    'answer_class' => $this->nullableString($assistant['answer_class'] ?? null) ?? 'explanation',
                    'confidence' => [
                        'score' => $this->safeFloat($confidence['score'] ?? $artifact->confidence_score),
                        'band' => $this->nullableString($confidence['band'] ?? null),
                    ],
                    'freshness_seconds' => $this->safeInt($payload['freshness_seconds'] ?? null),
                    'evidence_refs' => $evidenceRefs,
                    'missing_information' => $missingInformation,
                    'suggested_prompts' => $suggestedPrompts,
                    'created_at' => optional($artifact->created_at)?->toIso8601String(),
                ],
            ];

            if ($missingInformation !== []) {
                $transcript[] = [
                    'id' => 'warn_'.$artifact->id,
                    'type' => 'missing_info_warning',
                    'timestamp' => optional($artifact->created_at)?->toIso8601String(),
                    'items' => $missingInformation,
                ];
            }

            $confidenceScore = $this->safeFloat($confidence['score'] ?? $artifact->confidence_score);
            if ($artifact->state === 'incomplete' || ($confidenceScore !== null && $confidenceScore < 0.5)) {
                $transcript[] = [
                    'id' => 'degraded_'.$artifact->id,
                    'type' => 'degraded_response_notice',
                    'timestamp' => optional($artifact->created_at)?->toIso8601String(),
                    'reason' => 'Context is partial or confidence is reduced.',
                ];
            }

            if ($suggestedPrompts !== []) {
                $transcript[] = [
                    'id' => 'suggested_'.$artifact->id,
                    'type' => 'suggested_prompts',
                    'timestamp' => optional($artifact->created_at)?->toIso8601String(),
                    'prompts' => $suggestedPrompts,
                ];
            }
        }

        return [
            'conversation_id' => $conversation->id,
            'state' => $conversation->state,
            'surface' => $conversation->surface,
            'latest_artifact_id' => $conversation->latest_artifact_id,
            'last_activity_at' => optional($conversation->last_activity_at)?->toIso8601String(),
            'transcript' => $transcript,
        ];
    }

    private function resolveConversation(User $actor, string $tenantId, string $conversationId, ?string $uiSurface): AiConversation
    {
        $existing = AiConversation::query()->find($conversationId);
        if ($existing) {
            if ($existing->actor_id !== $actor->id || $existing->tenant_id !== $tenantId) {
                throw new AuthorizationException('forbidden_conversation_scope');
            }

            if ($uiSurface !== null && $uiSurface !== '') {
                $existing->surface = $uiSurface;
            }
            $existing->last_activity_at = now();
            $existing->save();

            return $existing;
        }

        return AiConversation::create([
            'id' => $conversationId,
            'tenant_id' => $tenantId,
            'actor_id' => $actor->id,
            'surface' => $uiSurface,
            'state' => 'active',
            'last_activity_at' => now(),
        ]);
    }

    private function normalizeConversationId(mixed $conversationId): string
    {
        if (! is_string($conversationId) || trim($conversationId) === '') {
            return (string) Str::ulid();
        }

        $value = trim($conversationId);
        if (strlen($value) <= 64) {
            return $value;
        }

        return substr($value, 0, 64);
    }

    /**
     * @return array{
     *  device_summary: array<string, mixed>,
     *  latest_telemetry: array<string, mixed>,
     *  command_failures: array<int, array<string, mixed>>,
     *  audit_events: array<int, array<string, mixed>>,
     *  system_health: array<string, mixed>
     * }
     */
    private function buildContextBundle(string $deviceId): array
    {
        $device = Device::query()
            ->with('user:id,email')
            ->find($deviceId);
        if (! $device) {
            throw new RuntimeException('device_not_found');
        }

        $latestTelemetry = DeviceTelemetryLatest::query()->find($deviceId);
        $metrics = is_array($latestTelemetry?->metrics) ? $latestTelemetry->metrics : [];
        $policyInSync = $this->policyInSync($device, $latestTelemetry);

        $deviceSummary = [
            'device_id' => $device->device_id,
            'device_name' => $device->device_name,
            'lifecycle_state' => $device->lifecycle_state,
            'last_seen' => optional($device->last_seen)?->toIso8601String(),
            'risk_score' => $this->safeFloat($device->risk_score),
            'compliance_status' => $device->compliance_status,
            'policy_in_sync' => $policyInSync,
            'resolved_compliance_status' => $device->compliance_status,
            'resolved_policy_in_sync' => $policyInSync,
            'owner_email' => $device->user?->email,
        ];

        $telemetry = [
            'device_id' => $device->device_id,
            'timestamp' => optional($latestTelemetry?->timestamp)?->toIso8601String(),
            'policy_hash' => $latestTelemetry?->policy_hash,
            'metrics' => [
                'cpu' => $this->safeFloat($metrics['cpu'] ?? null),
                'ram' => $this->safeFloat($metrics['ram'] ?? null),
                'disk_usage' => $this->safeFloat($metrics['disk_usage'] ?? null),
                'network_tx' => $this->safeFloat($metrics['network_tx'] ?? null),
                'network_rx' => $this->safeFloat($metrics['network_rx'] ?? null),
                'risk_score' => $this->safeFloat($metrics['risk_score'] ?? $device->risk_score),
                'policy_hash' => $latestTelemetry?->policy_hash ?? ($metrics['policy_hash'] ?? null),
            ],
        ];

        $commandFailures = Command::query()
            ->where('device_id', $deviceId)
            ->whereIn('state', ['failed', 'expired', 'rejected'])
            ->orderByDesc('updated_at')
            ->limit(20)
            ->get(['id', 'method', 'state', 'error_code', 'error_message', 'queued_at', 'completed_at'])
            ->map(function (Command $command): array {
                return [
                    'command_id' => $command->id,
                    'method' => $command->method,
                    'state' => $command->state,
                    'error_code' => $command->error_code,
                    'error_message' => $command->error_message,
                    'queued_at' => optional($command->queued_at)?->toIso8601String(),
                    'completed_at' => optional($command->completed_at)?->toIso8601String(),
                ];
            })
            ->values()
            ->all();

        $auditEvents = AuditTrail::query()
            ->where('device_id', $deviceId)
            ->orderByDesc('timestamp')
            ->limit(50)
            ->get(['audit_id', 'event_type', 'timestamp', 'actor', 'device_id'])
            ->map(function (AuditTrail $entry): array {
                return [
                    'id' => $entry->audit_id,
                    'event_type' => $entry->event_type,
                    'timestamp' => optional($entry->timestamp)?->toIso8601String(),
                    'actor' => $entry->actor,
                    'device_id' => $entry->device_id,
                    'source' => 'audit_trail',
                ];
            })
            ->values()
            ->all();

        $overview = $this->systemHealthService->overview();
        $systemHealth = array_merge($overview, [
            'components' => $this->systemHealthService->components(),
        ]);

        return [
            'device_summary' => $deviceSummary,
            'latest_telemetry' => $telemetry,
            'command_failures' => $commandFailures,
            'audit_events' => $auditEvents,
            'system_health' => $systemHealth,
        ];
    }

    private function policyInSync(Device $device, ?DeviceTelemetryLatest $latestTelemetry): ?bool
    {
        $expected = is_string($device->policy_hash) ? trim($device->policy_hash) : '';
        $reported = is_string($latestTelemetry?->policy_hash) ? trim($latestTelemetry->policy_hash) : '';

        if ($reported === '') {
            $reported = is_string($device->reported_policy_hash) ? trim($device->reported_policy_hash) : '';
        }

        if ($expected === '' || $reported === '') {
            return null;
        }

        return hash_equals($expected, $reported);
    }

    private function writeAuditLink(User $user, string $deviceId, string $artifactId, string $correlationId): void
    {
        $latest = AuditTrail::query()
            ->where('device_id', $deviceId)
            ->orderByDesc('timestamp')
            ->first();
        $prevHash = $latest?->hash;

        $payloadHash = hash('sha256', json_encode([
            'artifact_id' => $artifactId,
            'correlation_id' => $correlationId,
        ], JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE) ?: '');
        $chainHash = hash('sha256', ($prevHash ?? '').$payloadHash);

        AuditTrail::create([
            'audit_id' => 'ai_'.$artifactId,
            'actor' => (string) ($user->email ?: $user->id),
            'actor_id' => (string) $user->id,
            'device_id' => $deviceId,
            'event_type' => 'ai.copilot.answer',
            'payload_hash' => $payloadHash,
            'prev_hash' => $prevHash,
            'hash' => $chainHash,
            'signature' => null,
            'timestamp' => now(),
        ]);
    }

    private function safeFloat(mixed $value): ?float
    {
        if ($value === null || $value === '') {
            return null;
        }
        if (is_numeric($value)) {
            return (float) $value;
        }

        return null;
    }

    private function safeInt(mixed $value): ?int
    {
        if ($value === null || $value === '') {
            return null;
        }
        if (is_numeric($value)) {
            return (int) $value;
        }

        return null;
    }

    private function nullableString(mixed $value): ?string
    {
        if (! is_string($value)) {
            return null;
        }
        $trimmed = trim($value);
        return $trimmed === '' ? null : $trimmed;
    }

    private function parseIsoTimestamp(mixed $value): ?Carbon
    {
        if (! is_string($value) || trim($value) === '') {
            return null;
        }

        try {
            return Carbon::parse($value);
        } catch (\Throwable) {
            return null;
        }
    }

    /**
     * @return array<int, string>
     */
    private function safeStringArray(mixed $value): array
    {
        if (! is_array($value)) {
            return [];
        }

        return array_values(array_filter(
            array_map(
                fn ($item) => is_string($item) ? trim($item) : '',
                $value,
            ),
            fn ($item) => $item !== '',
        ));
    }
}
