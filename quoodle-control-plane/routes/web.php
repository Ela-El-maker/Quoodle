<?php

use App\Http\Controllers\Admin\DashboardController;
use App\Http\Controllers\Auth\JWKSController;
use App\Http\Controllers\Auth\WebLoginController;
use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return view('welcome');
});

Route::get('/.well-known/jwks.json', [JWKSController::class, 'show'])->name('jwks');

// Authentication Routes
Route::middleware('guest')->group(function () {
    Route::get('/login', [WebLoginController::class, 'showLoginForm'])->name('login');
    Route::post('/login', [WebLoginController::class, 'login']);
});

Route::post('/logout', [WebLoginController::class, 'logout'])->name('logout');

// Admin Dashboard Routes
Route::middleware(['auth', 'role:admin'])->prefix('admin')->name('admin.')->group(function () {
    Route::get('/dashboard', [DashboardController::class, 'index'])->name('dashboard');
    Route::get('/users', [DashboardController::class, 'users'])->name('users');
    Route::get('/devices', [DashboardController::class, 'devices'])->name('devices');
    Route::get('/commands', [DashboardController::class, 'commands'])->name('commands');
    Route::get('/alerts', [DashboardController::class, 'alerts'])->name('alerts');
    Route::get('/audit', [DashboardController::class, 'audit'])->name('audit');
});
