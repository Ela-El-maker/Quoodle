<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class DeviceUpdate extends Model
{
    use HasFactory, HasUlids;

    public $incrementing = false;
    protected $keyType = 'string';

    protected $fillable = [
        'device_id',
        'release_id',
        'version',
        'phase',
        'progress_percent',
        'progress_detail',
        'error_code',
        'error_message',
        'rollback_snapshot_id',
        'last_update_at',
    ];

    protected $casts = [
        'progress_percent' => 'integer',
        'error_code' => 'integer',
        'last_update_at' => 'datetime',
    ];
}
