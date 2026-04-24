<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AiToolCall extends Model
{
    use HasFactory, HasUlids;

    public $incrementing = false;

    protected $keyType = 'string';

    protected $table = 'ai_tool_calls';

    protected $fillable = [
        'tenant_id',
        'conversation_id',
        'artifact_id',
        'tool_name',
        'input_hash',
        'output_hash',
        'scope_hash',
        'duration_ms',
        'status',
        'error_code',
        'rows_returned',
    ];

    protected function casts(): array
    {
        return [
            'duration_ms' => 'integer',
            'rows_returned' => 'integer',
        ];
    }

    public function conversation(): BelongsTo
    {
        return $this->belongsTo(AiConversation::class, 'conversation_id', 'id');
    }
}

