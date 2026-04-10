<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class DeviceTelemetryLatest extends Model
{
    use HasFactory;

    protected $table = 'device_telemetry_latest';
    protected $primaryKey = 'device_id';
    public $incrementing = false;
    protected $keyType = 'string';
    public $timestamps = false;

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
        'updated_at',
    ];

    protected $casts = [
        'metrics' => 'array',
        'masked_fields' => 'array',
        'timestamp' => 'datetime',
        'updated_at' => 'datetime',
        'risk_score' => 'decimal:2',
    ];
}

