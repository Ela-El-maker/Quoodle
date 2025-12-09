<?php

use App\Http\Controllers\Auth\LoginController;
use App\Http\Controllers\Auth\RegisterController;
use App\Http\Controllers\Commands\CommandController;
use Illuminate\Support\Facades\Route;

Route::middleware('api')->group(function (): void {
    Route::post('/auth/register', [RegisterController::class, 'register']);
    Route::post('/auth/login', [LoginController::class, 'login']);
    Route::post('/register', [RegisterController::class, 'register']);
    Route::post('/login', [LoginController::class, 'login']);
    Route::post('/commands', [CommandController::class, 'store']);
});
