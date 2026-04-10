<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class TelemetryEvent extends Model
{
    use HasFactory, HasUlids;

    public $incrementing = false;
    protected $keyType = 'string';

    protected $fillable = [
        'device_id',
        'telemetry_scope',
        'schema_version',
        'session_id',
        'seq',
        'timestamp',
        'metrics',
        'masked_fields',
        'policy_hash',
        'risk_score',
        'presence_state',
        'connection_mode',
        'source',
    ];

    protected $casts = [
        'metrics' => 'array',
        'masked_fields' => 'array',
        'timestamp' => 'datetime',
        'risk_score' => 'decimal:2',
    ];
}

