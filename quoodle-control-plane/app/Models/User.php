<?php

namespace App\Models;

// use Illuminate\Contracts\Auth\MustVerifyEmail;
use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Illuminate\Database\Eloquent\Builder;

class User extends Authenticatable
{
    /** @use HasFactory<\Database\Factories\UserFactory> */
    use HasFactory, Notifiable, HasUlids;

    /**
     * Role constants
     */
    public const ROLE_ADMIN = 'admin';
    public const ROLE_OPERATOR = 'operator';
    public const ROLE_VIEWER = 'viewer';
    public const STATUS_ACTIVE = 'active';
    public const STATUS_INACTIVE = 'inactive';
    public const STATUS_PENDING = 'pending';

    /**
     * Valid roles
     */
    public const ROLES = [
        self::ROLE_ADMIN,
        self::ROLE_OPERATOR,
        self::ROLE_VIEWER,
    ];

    /**
     * Indicates if the IDs are auto-incrementing.
     */
    public $incrementing = false;

    /**
     * The data type of the primary key.
     */
    protected $keyType = 'string';

    /**
     * The attributes that are mass assignable.
     *
     * @var list<string>
     */
    protected $fillable = [
        'display_name',
        'email',
        'role',
        'account_status',
        'deactivated_at',
        'invited_by',
        'two_factor_enabled',
        'two_factor_secret',
    ];

    /**
     * The attributes that should be hidden for serialization.
     *
     * @var list<string>
     */
    protected $hidden = [
        'remember_token',
    ];

    /**
     * Get the attributes that should be cast.
     *
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'two_factor_enabled' => 'boolean',
            'two_factor_secret' => 'encrypted',
            'deactivated_at' => 'datetime',
        ];
    }

    // =========================================================================
    // Role Check Methods
    // =========================================================================

    /**
     * Check if user has admin role.
     */
    public function isAdmin(): bool
    {
        return $this->role === self::ROLE_ADMIN;
    }

    /**
     * Check if user has operator role.
     */
    public function isOperator(): bool
    {
        return $this->role === self::ROLE_OPERATOR;
    }

    /**
     * Check if user has viewer role.
     */
    public function isViewer(): bool
    {
        return $this->role === self::ROLE_VIEWER;
    }

    public function isActive(): bool
    {
        return (string) ($this->account_status ?? self::STATUS_ACTIVE) === self::STATUS_ACTIVE;
    }

    /**
     * Check if user has at least operator privileges (admin or operator).
     */
    public function canOperate(): bool
    {
        return in_array($this->role, [self::ROLE_ADMIN, self::ROLE_OPERATOR], true);
    }

    /**
     * Check if user has a specific role or higher.
     *
     * Role hierarchy: admin > operator > viewer
     */
    public function hasRoleOrHigher(string $role): bool
    {
        $hierarchy = [
            self::ROLE_VIEWER => 1,
            self::ROLE_OPERATOR => 2,
            self::ROLE_ADMIN => 3,
        ];

        $userLevel = $hierarchy[$this->role] ?? 0;
        $requiredLevel = $hierarchy[$role] ?? 0;

        return $userLevel >= $requiredLevel;
    }

    // =========================================================================
    // Permission Methods
    // =========================================================================

    /**
     * Check if user can execute commands on devices.
     */
    public function canExecuteCommands(): bool
    {
        return $this->canOperate();
    }

    /**
     * Check if user can manage policies.
     */
    public function canManagePolicies(): bool
    {
        return $this->isAdmin();
    }

    /**
     * Check if user can manage users.
     */
    public function canManageUsers(): bool
    {
        return $this->isAdmin();
    }

    /**
     * Check if user can view devices and telemetry.
     */
    public function canViewDevices(): bool
    {
        return true; // All authenticated users can view
    }

    /**
     * Check if user can claim/manage devices.
     */
    public function canManageDevices(): bool
    {
        return $this->canOperate();
    }

    /**
     * Check if user can acknowledge alerts.
     */
    public function canAcknowledgeAlerts(): bool
    {
        return $this->canOperate();
    }

    // =========================================================================
    // Relationships
    // =========================================================================

    /**
     * Get the devices owned by this user.
     */
    public function devices()
    {
        return $this->hasMany(Device::class, 'user_id', 'id');
    }

    /**
     * Mobile devices used by this user (app sessions).
     */
    public function mobileDevices()
    {
        return $this->hasMany(MobileDevice::class, 'user_id', 'id');
    }

    /**
     * Links between user mobile devices and agent devices.
     */
    public function deviceLinks()
    {
        return $this->hasMany(DeviceLink::class, 'user_id', 'id');
    }

    public function deviceAccessGrants()
    {
        return $this->hasMany(TeamMemberDeviceAccess::class, 'user_id', 'id');
    }

    /**
     * Get the commands issued by this user.
     */
    public function commands()
    {
        return $this->hasMany(Command::class, 'user_id', 'id');
    }

    /**
     * Get the scheduled jobs created by this user.
     */
    public function scheduledJobs()
    {
        return $this->hasMany(ScheduledJob::class, 'created_by_user_id', 'id');
    }

    // =========================================================================
    // Query Scopes
    // =========================================================================

    /**
     * Scope to filter by role.
     */
    public function scopeRole(Builder $query, string $role): Builder
    {
        return $query->where('role', $role);
    }

    /**
     * Scope to get admins.
     */
    public function scopeAdmins(Builder $query): Builder
    {
        return $query->role(self::ROLE_ADMIN);
    }

    /**
     * Scope to get operators.
     */
    public function scopeOperators(Builder $query): Builder
    {
        return $query->role(self::ROLE_OPERATOR);
    }

    /**
     * Scope to get viewers.
     */
    public function scopeViewers(Builder $query): Builder
    {
        return $query->role(self::ROLE_VIEWER);
    }
}
