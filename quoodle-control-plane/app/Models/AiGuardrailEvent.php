<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AiGuardrailEvent extends Model
{
    use HasFactory, HasUlids;

    public $incrementing = false;

    protected $keyType = 'string';

    protected $table = 'ai_guardrail_events';

    protected $fillable = [
        'tenant_id',
        'conversation_id',
        'artifact_id',
        'event_type',
        'severity',
        'detail_json',
    ];

    protected function casts(): array
    {
        return [
            'detail_json' => 'array',
        ];
    }

    public function conversation(): BelongsTo
    {
        return $this->belongsTo(AiConversation::class, 'conversation_id', 'id');
    }
}

