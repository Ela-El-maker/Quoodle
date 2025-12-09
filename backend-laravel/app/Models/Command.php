<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Command extends Model
{
    use HasFactory, HasUlids;

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'client_message_id',
        'device_id',
        'method',
        'params',
        'sensitive',
        'state',
        'status',
        'reason',
        'trace_id',
        'queued_at',
        'dispatched_at',
    ];

    protected $casts = [
        'params' => 'array',
        'sensitive' => 'boolean',
        'queued_at' => 'datetime',
        'dispatched_at' => 'datetime',
    ];
}
