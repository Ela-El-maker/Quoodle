<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class IntegrationWebhookDelivery extends Model
{
    use HasFactory, HasUlids;

    public const STATUS_PENDING = 'pending';
    public const STATUS_RETRYING = 'retrying';
    public const STATUS_SENT = 'sent';
    public const STATUS_DEAD_LETTER = 'dead_letter';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'endpoint_id',
        'event_type',
        'event_id',
        'payload_json',
        'attempt',
        'max_attempts',
        'status',
        'next_attempt_at',
        'http_status',
        'latency_ms',
        'response_body',
        'last_error',
        'replayed_from_delivery_id',
        'sent_at',
        'delivered_at',
    ];

    protected function casts(): array
    {
        return [
            'payload_json' => 'array',
            'attempt' => 'integer',
            'max_attempts' => 'integer',
            'http_status' => 'integer',
            'latency_ms' => 'integer',
            'next_attempt_at' => 'datetime',
            'sent_at' => 'datetime',
            'delivered_at' => 'datetime',
        ];
    }

    public function endpoint(): BelongsTo
    {
        return $this->belongsTo(IntegrationWebhookEndpoint::class, 'endpoint_id', 'id');
    }

    public function replayedFrom(): BelongsTo
    {
        return $this->belongsTo(self::class, 'replayed_from_delivery_id', 'id');
    }
}
