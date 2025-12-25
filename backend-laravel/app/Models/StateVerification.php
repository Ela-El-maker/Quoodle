<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class StateVerification extends Model
{
    use HasFactory, HasUlids;

    public $incrementing = false;
    protected $keyType = 'string';

    protected $fillable = [
        'device_id',
        'command_id',
        'method',
        'expected_policy_hash',
        'not_before',
        'status',
        'details',
        'resolved_at',
    ];

    protected $casts = [
        'not_before' => 'datetime',
        'resolved_at' => 'datetime',
    ];
}
