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
    Route::get('/devices/{device}', [DashboardController::class, 'deviceShow'])->name('devices.show');
    Route::get('/commands', [DashboardController::class, 'commands'])->name('commands');
    Route::get('/commands/export', [DashboardController::class, 'exportCommands'])->name('commands.export');
    Route::post('/commands/execute', [DashboardController::class, 'commandExecute'])->name('commands.execute');
    Route::get('/commands/{command}', [DashboardController::class, 'commandShow'])->name('commands.show');
    Route::get('/alerts', [DashboardController::class, 'alerts'])->name('alerts');
    Route::get('/alerts/{alert}', [DashboardController::class, 'alertShow'])->name('alerts.show');
    Route::post('/alerts/{alert}/ack', [DashboardController::class, 'ackAlert'])->name('alerts.ack');
    Route::get('/audit', [DashboardController::class, 'audit'])->name('audit');
    Route::get('/audit/export', [DashboardController::class, 'exportAudit'])->name('audit.export');
    Route::get('/compliance', [DashboardController::class, 'compliance'])->name('compliance');
    Route::get('/compliance/export', [DashboardController::class, 'exportCompliance'])->name('compliance.export');
    Route::get('/system', [DashboardController::class, 'system'])->name('system');
    Route::get('/investigations', [DashboardController::class, 'investigations'])->name('investigations');
    Route::get('/policy', [DashboardController::class, 'policy'])->name('policy');
});
