<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;

class ScheduledJob extends Model
{
    use HasFactory, HasUlids;

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'created_by_user_id',
        'created_by_role',
        'name',
        'method',
        'params',
        'target_type',
        'target_ids',
        'cron_expression',
        'timezone',
        'enabled',
        'last_run_at',
        'next_run_at',
    ];

    protected $casts = [
        'params' => 'array',
        'target_ids' => 'array',
        'enabled' => 'boolean',
        'last_run_at' => 'datetime',
        'next_run_at' => 'datetime',
    ];

    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by_user_id', 'id');
    }

    public function runs(): HasMany
    {
        return $this->hasMany(ScheduledJobRun::class, 'job_id', 'id');
    }

    public function latestRun(): HasOne
    {
        return $this->hasOne(ScheduledJobRun::class, 'job_id', 'id')->latestOfMany('scheduled_for');
    }
}
