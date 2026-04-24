<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class AiArtifact extends Model
{
    use HasFactory, HasUlids;

    public $incrementing = false;

    protected $keyType = 'string';

    protected $table = 'ai_artifacts';

    protected $fillable = [
        'tenant_id',
        'conversation_id',
        'actor_id',
        'artifact_type',
        'state',
        'subject_type',
        'subject_id',
        'confidence_score',
        'risk_score',
        'title',
        'summary',
        'payload_json',
        'prompt_hash',
        'tool_call_set_hash',
        'provider',
        'model',
        'expires_at',
    ];

    protected function casts(): array
    {
        return [
            'payload_json' => 'array',
            'confidence_score' => 'decimal:4',
            'risk_score' => 'integer',
            'expires_at' => 'datetime',
        ];
    }

    public function conversation(): BelongsTo
    {
        return $this->belongsTo(AiConversation::class, 'conversation_id', 'id');
    }

    public function actor(): BelongsTo
    {
        return $this->belongsTo(User::class, 'actor_id', 'id');
    }

    public function evidenceRefs(): HasMany
    {
        return $this->hasMany(AiEvidenceRef::class, 'artifact_id', 'id');
    }
}

