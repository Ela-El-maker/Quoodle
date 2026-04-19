<?php

namespace App\Http\Middleware;

use App\Services\Auth\RolePermissionService;
use Closure;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class EnsurePermission
{
    public function __construct(private readonly RolePermissionService $permissions)
    {
    }

    public function handle(Request $request, Closure $next, string $permission): Response
    {
        $user = $request->user();
        if (! $user) {
            return $this->error('AUTHENTICATION_REQUIRED', 'Authentication required', 401);
        }

        if (! $this->permissions->userCan($user, $permission)) {
            return $this->error('INSUFFICIENT_PERMISSIONS', 'Permission denied', 403);
        }

        return $next($request);
    }

    private function error(string $code, string $message, int $status): JsonResponse
    {
        return response()->json([
            'error' => [
                'code' => $code,
                'message' => $message,
            ],
        ], $status);
    }
}