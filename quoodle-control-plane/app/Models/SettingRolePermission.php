<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;

class SettingRolePermission extends Model
{
    use HasFactory;

    protected $fillable = [
        'role',
        'permission_key',
        'allowed',
        'updated_by',
    ];

    protected function casts(): array
    {
        return [
            'allowed' => 'boolean',
        ];
    }
}