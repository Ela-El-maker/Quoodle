<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class IntegrationWebhookSubscription extends Model
{
    use HasFactory;

    protected $fillable = [
        'endpoint_id',
        'event_type',
    ];

    public function endpoint(): BelongsTo
    {
        return $this->belongsTo(IntegrationWebhookEndpoint::class, 'endpoint_id', 'id');
    }
}
