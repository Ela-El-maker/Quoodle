<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class SettingPolicyEntry extends Model
{
    use HasFactory, HasUlids;

    public $incrementing = false;

    protected $keyType = 'string';

    protected $fillable = [
        'policy_key',
        'policy_value',
        'scope',
        'value_type',
        'description',
        'is_mutable',
        'created_by',
        'updated_by',
    ];

    protected function casts(): array
    {
        return [
            'is_mutable' => 'boolean',
        ];
    }
}