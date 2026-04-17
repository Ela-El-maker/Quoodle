<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class ScheduledJobRunItem extends Model
{
    use HasFactory, HasUlids;

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'run_id',
        'device_id',
        'command_id',
        'status',
        'error_message',
        'result_summary',
        'started_at',
        'finished_at',
    ];

    protected $casts = [
        'result_summary' => 'array',
        'started_at' => 'datetime',
        'finished_at' => 'datetime',
    ];

    public function run(): BelongsTo
    {
        return $this->belongsTo(ScheduledJobRun::class, 'run_id', 'id');
    }

    public function command(): BelongsTo
    {
        return $this->belongsTo(Command::class, 'command_id', 'id');
    }

    public function device(): BelongsTo
    {
        return $this->belongsTo(Device::class, 'device_id', 'device_id');
    }
}
