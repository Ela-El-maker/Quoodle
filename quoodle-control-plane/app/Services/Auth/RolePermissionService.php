<?php

namespace App\Services\Auth;

use App\Models\SettingRolePermission;
use App\Models\User;
use Illuminate\Support\Collection;

class RolePermissionService
{
    /**
     * @return array<string, bool>
     */
    public function permissionsForRole(string $role): array
    {
        $role = strtolower(trim($role));
        if ($role === '') {
            return [];
        }

        $rows = SettingRolePermission::query()
            ->where('role', $role)
            ->get(['permission_key', 'allowed']);

        if ($rows->isEmpty()) {
            return $this->defaultMatrix()[$role] ?? [];
        }

        $permissions = [];
        foreach ($rows as $row) {
            $permissions[(string) $row->permission_key] = (bool) $row->allowed;
        }

        return $permissions;
    }

    public function userCan(?User $user, string $permission): bool
    {
        if (! $user) {
            return false;
        }

        if ($user->role === User::ROLE_ADMIN) {
            return true;
        }

        if (method_exists($user, 'isActive') && ! $user->isActive()) {
            return false;
        }

        return (bool) ($this->permissionsForRole((string) $user->role)[$permission] ?? false);
    }

    /**
     * @return array<string, array<string, bool>>
     */
    public function matrix(): array
    {
        $roles = [User::ROLE_ADMIN, User::ROLE_OPERATOR, User::ROLE_VIEWER];
        $defaults = $this->defaultMatrix();
        $result = [];

        foreach ($roles as $role) {
            $rolePermissions = $defaults[$role] ?? [];
            $stored = $this->permissionsForRole($role);
            if (! empty($stored)) {
                $rolePermissions = array_merge($rolePermissions, $stored);
            }
            ksort($rolePermissions);
            $result[$role] = $rolePermissions;
        }

        return $result;
    }

    /**
     * @param  array<string, bool>  $permissions
     */
    public function replaceRolePermissions(string $role, array $permissions, ?string $actorId = null): void
    {
        $role = strtolower(trim($role));
        if (! in_array($role, [User::ROLE_ADMIN, User::ROLE_OPERATOR, User::ROLE_VIEWER], true)) {
            return;
        }

        SettingRolePermission::query()->where('role', $role)->delete();

        $payload = [];
        $now = now();
        foreach ($permissions as $key => $allowed) {
            $payload[] = [
                'role' => $role,
                'permission_key' => (string) $key,
                'allowed' => (bool) $allowed,
                'updated_by' => $actorId,
                'created_at' => $now,
                'updated_at' => $now,
            ];
        }

        if ($payload !== []) {
            SettingRolePermission::query()->insert($payload);
        }
    }

    /**
     * @return array<string, array<string, bool>>
     */
    private function defaultMatrix(): array
    {
        return [
            User::ROLE_ADMIN => [
                'view_devices' => true,
                'manage_devices' => true,
                'send_commands' => true,
                'send_sensitive_commands' => true,
                'view_alerts' => true,
                'acknowledge_alerts' => true,
                'view_compliance' => true,
                'manage_compliance' => true,
                'view_audit' => true,
                'manage_users' => true,
                'manage_settings' => true,
                'export_data' => true,
                'pair_devices' => true,
            ],
            User::ROLE_OPERATOR => [
                'view_devices' => true,
                'manage_devices' => false,
                'send_commands' => true,
                'send_sensitive_commands' => false,
                'view_alerts' => true,
                'acknowledge_alerts' => true,
                'view_compliance' => true,
                'manage_compliance' => false,
                'view_audit' => true,
                'manage_users' => false,
                'manage_settings' => false,
                'export_data' => true,
                'pair_devices' => true,
            ],
            User::ROLE_VIEWER => [
                'view_devices' => true,
                'manage_devices' => false,
                'send_commands' => false,
                'send_sensitive_commands' => false,
                'view_alerts' => false,
                'acknowledge_alerts' => false,
                'view_compliance' => true,
                'manage_compliance' => false,
                'view_audit' => true,
                'manage_users' => false,
                'manage_settings' => false,
                'export_data' => false,
                'pair_devices' => true,
            ],
        ];
    }
}