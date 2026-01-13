<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Telemetry extends Model
{
    use HasFactory, HasUlids;

    public $incrementing = false;
    protected $keyType = 'string';

    protected $fillable = [
        'device_id',
        'metrics',
        'captured_at',
    ];

    protected $casts = [
        'metrics' => 'array',
        'captured_at' => 'datetime',
    ];
}
