<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class TelemetryRollup extends Model
{
    use HasFactory, HasUlids;

    public $incrementing = false;
    protected $keyType = 'string';

    protected $fillable = [
        'device_id',
        'bucket_start',
        'bucket_minutes',
        'samples',
        'avg_cpu',
        'avg_ram',
        'avg_disk_usage',
        'avg_network_tx',
        'avg_network_rx',
        'avg_risk_score',
        'max_cpu',
        'presence_state',
    ];

    protected $casts = [
        'bucket_start' => 'datetime',
        'samples' => 'integer',
        'avg_cpu' => 'decimal:2',
        'avg_ram' => 'decimal:2',
        'avg_disk_usage' => 'decimal:2',
        'avg_network_tx' => 'decimal:2',
        'avg_network_rx' => 'decimal:2',
        'avg_risk_score' => 'decimal:2',
        'max_cpu' => 'decimal:2',
    ];
}

