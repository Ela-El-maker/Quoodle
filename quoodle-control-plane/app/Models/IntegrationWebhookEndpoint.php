<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;

class IntegrationWebhookEndpoint extends Model
{
    use HasFactory, HasUlids;

    public const STATUS_ACTIVE = 'active';
    public const STATUS_PAUSED = 'paused';
    public const STATUS_FAILING = 'failing';

    public const RETRY_EXPONENTIAL = 'exponential';
    public const RETRY_LINEAR = 'linear';
    public const RETRY_NONE = 'none';

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'name',
        'url',
        'status',
        'signing_algo',
        'retry_policy',
        'max_retries',
        'timeout_ms',
        'signing_secret_encrypted',
        'created_by',
        'updated_by',
    ];

    protected $hidden = [
        'signing_secret_encrypted',
    ];

    protected function casts(): array
    {
        return [
            'max_retries' => 'integer',
            'timeout_ms' => 'integer',
            'signing_secret_encrypted' => 'encrypted',
        ];
    }

    public function subscriptions(): HasMany
    {
        return $this->hasMany(IntegrationWebhookSubscription::class, 'endpoint_id', 'id');
    }

    public function deliveries(): HasMany
    {
        return $this->hasMany(IntegrationWebhookDelivery::class, 'endpoint_id', 'id');
    }

    public function latestDelivery(): HasOne
    {
        return $this->hasOne(IntegrationWebhookDelivery::class, 'endpoint_id', 'id')
            ->orderByDesc('created_at')
            ->orderByDesc('id');
    }

    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by', 'id');
    }

    public function updater(): BelongsTo
    {
        return $this->belongsTo(User::class, 'updated_by', 'id');
    }

    public function secretMasked(): string
    {
        $secret = (string) ($this->signing_secret_encrypted ?? '');
        if ($secret === '') {
            return '';
        }

        if (strlen($secret) <= 8) {
            return str_repeat('*', strlen($secret));
        }

        return substr($secret, 0, 4).str_repeat('*', max(strlen($secret) - 8, 4)).substr($secret, -4);
    }
}
