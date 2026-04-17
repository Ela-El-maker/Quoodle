<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class ScheduledJobRun extends Model
{
    use HasFactory, HasUlids;

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'job_id',
        'trigger',
        'scheduled_for',
        'status',
        'started_at',
        'finished_at',
        'total_targets',
        'dispatched_count',
        'failed_count',
        'result_summary',
        'error_message',
    ];

    protected $casts = [
        'scheduled_for' => 'datetime',
        'started_at' => 'datetime',
        'finished_at' => 'datetime',
        'result_summary' => 'array',
        'total_targets' => 'integer',
        'dispatched_count' => 'integer',
        'failed_count' => 'integer',
    ];

    public function job(): BelongsTo
    {
        return $this->belongsTo(ScheduledJob::class, 'job_id', 'id');
    }

    public function items(): HasMany
    {
        return $this->hasMany(ScheduledJobRunItem::class, 'run_id', 'id');
    }
}
