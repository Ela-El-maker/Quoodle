<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class DeviceLink extends Model
{
    use HasFactory, HasUlids;

    public $incrementing = false;
    protected $keyType = 'string';

    protected $fillable = [
        'user_id',
        'mobile_device_id',
        'device_id',
        'linked_via',
        'linked_at',
    ];

    protected $casts = [
        'linked_at' => 'datetime',
    ];

    public function user()
    {
        return $this->belongsTo(User::class);
    }

    public function mobileDevice()
    {
        return $this->belongsTo(MobileDevice::class, 'mobile_device_id', 'id');
    }

    public function device()
    {
        return $this->belongsTo(Device::class, 'device_id', 'device_id');
    }
}
