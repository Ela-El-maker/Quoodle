<?php

use App\Http\Controllers\Auth\JWKSController;
use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return response()->json([
        'service' => 'quoodle-control-plane',
        'mode' => 'api-only',
        'ui_url' => env('CONTROL_PLANE_UI_URL', 'http://localhost:3000'),
        'message' => 'Control Plane UI is now served by Next.js.',
    ]);
});

Route::get('/.well-known/jwks.json', [JWKSController::class, 'show'])->name('jwks');
