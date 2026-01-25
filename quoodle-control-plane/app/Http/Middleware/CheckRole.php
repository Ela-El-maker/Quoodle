<?php

declare(strict_types=1);

namespace App\Http\Middleware;

use App\Models\User;
use Closure;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Symfony\Component\HttpFoundation\Response;

/**
 * Role-based authorization middleware.
 *
 * Validates that the authenticated user has the required role level.
 * Supports both exact role matching and "at least" hierarchical checks.
 *
 * Usage in routes:
 *   ->middleware('role:admin')           // Admin only
 *   ->middleware('role:operator')        // Operator or admin
 *   ->middleware('role:viewer')          // Any authenticated user
 */
class CheckRole
{
    /**
     * Role hierarchy levels (higher = more permissions).
     */
    private const ROLE_HIERARCHY = [
        User::ROLE_VIEWER => 1,
        User::ROLE_OPERATOR => 2,
        User::ROLE_ADMIN => 3,
    ];

    /**
     * Handle an incoming request.
     *
     * @param  \Closure(\Illuminate\Http\Request): (\Symfony\Component\HttpFoundation\Response)  $next
     * @param  string  $role  Required minimum role level
     */
    public function handle(Request $request, Closure $next, string $role): Response
    {
        /** @var User|null $user */
        $user = Auth::user();

        // Must be authenticated (should already be handled by jwt.auth)
        if (!$user) {
            if ($request->expectsJson()) {
                return $this->unauthorizedResponse('AUTHENTICATION_REQUIRED', 'Authentication required');
            } else {
                return redirect()->guest(route('login'));
            }
        }

        // Validate the required role exists
        if (!isset(self::ROLE_HIERARCHY[$role])) {
            // Log invalid role configuration
            report(new \InvalidArgumentException("Invalid role configuration: {$role}"));
            if ($request->expectsJson()) {
                return $this->errorResponse('INVALID_ROLE_CONFIG', 'Server configuration error');
            } else {
                abort(500, 'Server configuration error');
            }
        }

        // Check if user's role meets the minimum requirement
        $userLevel = self::ROLE_HIERARCHY[$user->role] ?? 0;
        $requiredLevel = self::ROLE_HIERARCHY[$role];

        if ($userLevel < $requiredLevel) {
            if ($request->expectsJson()) {
                return $this->forbiddenResponse(
                    'INSUFFICIENT_PERMISSIONS',
                    "This action requires {$role} role or higher",
                    [
                        'required_role' => $role,
                        'user_role' => $user->role,
                    ]
                );
            } else {
                abort(403, "This action requires {$role} role or higher");
            }
        }

        return $next($request);
    }

    /**
     * Build a 401 Unauthorized JSON response.
     */
    private function unauthorizedResponse(string $code, string $message): JsonResponse
    {
        return response()->json([
            'error' => [
                'code' => $code,
                'message' => $message,
            ],
        ], 401);
    }

    /**
     * Build a 403 Forbidden JSON response.
     */
    private function forbiddenResponse(string $code, string $message, array $details = []): JsonResponse
    {
        $error = [
            'code' => $code,
            'message' => $message,
        ];

        if (!empty($details) && config('app.debug')) {
            $error['details'] = $details;
        }

        return response()->json(['error' => $error], 403);
    }

    /**
     * Build a 500 error JSON response.
     */
    private function errorResponse(string $code, string $message): JsonResponse
    {
        return response()->json([
            'error' => [
                'code' => $code,
                'message' => $message,
            ],
        ], 500);
    }
}
