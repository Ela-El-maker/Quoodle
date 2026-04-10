<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class TelemetryIngestError extends Model
{
    use HasFactory, HasUlids;

    public $incrementing = false;
    protected $keyType = 'string';

    protected $fillable = [
        'device_id',
        'timestamp',
        'reason',
        'details',
        'source',
    ];

    protected $casts = [
        'timestamp' => 'datetime',
        'details' => 'array',
    ];
}

