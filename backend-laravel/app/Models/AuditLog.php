<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class AuditLog extends Model
{
    use HasFactory, HasUlids;

    public $incrementing = false;
    protected $keyType = 'string';

    protected $fillable = [
        'audit_id',
        'actor',
        'actor_id',
        'event_type',
        'payload_hash',
        'signature',
        'timestamp',
    ];

    protected $casts = [
        'timestamp' => 'datetime',
    ];
}
