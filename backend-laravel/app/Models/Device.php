<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class Device extends Model
{
    use HasFactory;

    protected $primaryKey = 'device_id';
    public $incrementing = false;
    protected $keyType = 'string';

    protected $fillable = [
        'device_id',
        'user_id',
        'device_name',
        'hwid',
        'hwid_hash',
        'ed25519_pubkey_b64',
        'lifecycle_state',
        'last_seen',
        'agent_version',
        'os_build',
        'policy_hash',
        'compliance_status',
        'risk_score',
    ];

    protected $casts = [
        'last_seen' => 'datetime',
        'risk_score' => 'decimal:2',
    ];
}
