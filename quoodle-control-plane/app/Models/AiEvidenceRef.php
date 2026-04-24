<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AiEvidenceRef extends Model
{
    use HasFactory, HasUlids;

    public $incrementing = false;

    protected $keyType = 'string';

    protected $table = 'ai_evidence_refs';

    protected $fillable = [
        'artifact_id',
        'tenant_id',
        'source_type',
        'source_id',
        'source_ts',
        'excerpt_summary',
        'excerpt_hash',
        'confidence_weight',
        'freshness_seconds',
        'uri',
        'rank',
    ];

    protected function casts(): array
    {
        return [
            'source_ts' => 'datetime',
            'confidence_weight' => 'decimal:4',
            'freshness_seconds' => 'integer',
            'rank' => 'integer',
        ];
    }

    public function artifact(): BelongsTo
    {
        return $this->belongsTo(AiArtifact::class, 'artifact_id', 'id');
    }
}

