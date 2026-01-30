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
        'reported_policy_hash',
        'compliance_status',
        'risk_score',
    ];

    protected $casts = [
        'last_seen' => 'datetime',
        'risk_score' => 'decimal:2',
    ];

    // =========================================================================
    // Relationships
    // =========================================================================

    /**
     * Get the user that owns this device.
     */
    public function user()
    {
        return $this->belongsTo(User::class, 'user_id', 'id');
    }

    /**
     * Get the commands for this device.
     */
    public function commands()
    {
        return $this->hasMany(Command::class, 'device_id', 'device_id');
    }

    /**
     * Get the alerts for this device.
     */
    public function alerts()
    {
        return $this->hasMany(Alert::class, 'device_id', 'device_id');
    }

    public function links()
    {
        return $this->hasMany(DeviceLink::class, 'device_id', 'device_id');
    }
}
