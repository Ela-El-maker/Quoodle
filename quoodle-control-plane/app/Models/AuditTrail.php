<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class AuditTrail extends Model
{
    use HasFactory, HasUlids;

    public $incrementing = false;
    protected $keyType = 'string';

    protected $table = 'audit_trail';

    protected $fillable = [
        'audit_id',
        'actor',
        'actor_id',
        'device_id',
        'event_type',
        'payload_hash',
        'prev_hash',
        'hash',
        'signature',
        'timestamp',
    ];

    protected $casts = [
        'timestamp' => 'datetime',
    ];
}
