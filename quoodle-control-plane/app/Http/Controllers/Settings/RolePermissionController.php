<?php

namespace App\Http\Controllers\Settings;

use App\Http\Controllers\Controller;
use App\Models\User;
use App\Services\Auth\RolePermissionService;
use App\Services\Settings\SettingsAuditService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

final class RolePermissionController extends Controller
{
    public function __construct(
        private readonly RolePermissionService $permissions,
        private readonly SettingsAuditService $audit,
    ) {
    }

    public function index(): JsonResponse
    {
        return response()->json([
            'matrix' => $this->permissions->matrix(),
        ]);
    }

    public function show(string $role): JsonResponse
    {
        $normalizedRole = strtolower(trim($role));
        if (! in_array($normalizedRole, User::ROLES, true)) {
            return response()->json(['message' => 'invalid_role'], 422);
        }

        return response()->json([
            'role' => $normalizedRole,
            'permissions' => $this->permissions->permissionsForRole($normalizedRole),
        ]);
    }

    public function update(Request $request, string $role): JsonResponse
    {
        $normalizedRole = strtolower(trim($role));
        if (! in_array($normalizedRole, User::ROLES, true)) {
            return response()->json(['message' => 'invalid_role'], 422);
        }

        $validator = Validator::make($request->all(), [
            'permissions' => ['required', 'array', 'min:1'],
            'permissions.*' => ['boolean'],
        ]);

        if ($validator->fails()) {
            return response()->json(['message' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $before = $this->permissions->permissionsForRole($normalizedRole);
        $after = $validator->validated()['permissions'];
        $user = $request->user();

        $this->permissions->replaceRolePermissions($normalizedRole, $after, $user?->id);

        $this->audit->record(
            $user,
            'setting_role_permissions',
            $normalizedRole,
            'replace',
            $before,
            $after,
        );

        return response()->json([
            'role' => $normalizedRole,
            'permissions' => $this->permissions->permissionsForRole($normalizedRole),
        ]);
    }
}
