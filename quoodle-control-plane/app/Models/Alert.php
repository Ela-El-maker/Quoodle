<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Alert extends Model
{
    use HasFactory, HasUlids;

    public $incrementing = false;
    protected $keyType = 'string';

    protected $fillable = [
        'alert_id',
        'device_id',
        'severity',
        'category',
        'message',
        'timestamp',
        'acknowledged',
    ];

    protected $casts = [
        'timestamp' => 'datetime',
        'acknowledged' => 'boolean',
    ];
}
