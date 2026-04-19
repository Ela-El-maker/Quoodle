<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class SettingComplianceThreshold extends Model
{
    use HasFactory, HasUlids;

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'control',
        'metric',
        'threshold',
        'unit',
        'severity',
        'enabled',
        'created_by',
        'updated_by',
    ];

    protected function casts(): array
    {
        return [
            'threshold' => 'float',
            'enabled' => 'boolean',
        ];
    }
}