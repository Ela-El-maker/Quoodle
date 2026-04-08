<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Auth;

class MeController extends Controller
{
    public function __invoke(): JsonResponse
    {
        $user = Auth::user();

        return response()->json([
            'user_id' => $user->id,
            'email' => $user->email,
            'display_name' => $user->display_name,
            'user_role' => $user->role,
            'two_factor_enabled' => (bool) ($user->two_factor_enabled ?? false),
        ]);
    }
}
