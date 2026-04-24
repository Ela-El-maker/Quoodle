<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AiModelCall extends Model
{
    use HasFactory, HasUlids;

    public $incrementing = false;

    protected $keyType = 'string';

    protected $table = 'ai_model_calls';

    protected $fillable = [
        'tenant_id',
        'conversation_id',
        'artifact_id',
        'provider',
        'model',
        'api_mode',
        'provider_response_id',
        'request_hash',
        'tool_call_set_hash',
        'input_tokens',
        'output_tokens',
        'latency_ms',
        'status',
        'error_code',
        'reasoning_summary_json',
    ];

    protected function casts(): array
    {
        return [
            'input_tokens' => 'integer',
            'output_tokens' => 'integer',
            'latency_ms' => 'integer',
            'reasoning_summary_json' => 'array',
        ];
    }

    public function conversation(): BelongsTo
    {
        return $this->belongsTo(AiConversation::class, 'conversation_id', 'id');
    }
}

