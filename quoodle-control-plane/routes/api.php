<?php

use App\Http\Controllers\Auth\LoginController;
use App\Http\Controllers\Auth\RegisterController;
use App\Http\Controllers\Auth\TokenController;
use App\Http\Controllers\Auth\TwoFactorController;
use App\Http\Controllers\Alerts\AlertsController;
use App\Http\Controllers\Commands\CommandController;
use App\Http\Controllers\Commands\CommandQueryController;
use App\Http\Controllers\Devices\DeviceController;
use App\Http\Controllers\Devices\PairingController;
use App\Http\Controllers\Policy\PolicyController;
use App\Http\Controllers\Compliance\ComplianceController;
use App\Http\Controllers\Audit\AuditTrailController;
use App\Http\Controllers\Telemetry\TelemetryController;
use App\Http\Controllers\Updates\UpdateController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Public Routes (No Authentication Required)
|--------------------------------------------------------------------------
*/
Route::middleware('api')->group(function (): void {
    // Authentication endpoints
    Route::post('/register', [RegisterController::class, 'register']);
    Route::post('/login', [LoginController::class, 'login']);
    Route::post('/token/refresh', [TokenController::class, 'refresh']);
    Route::post('/pair/request', [PairingController::class, 'request']);
    Route::post('/agent/token', [PairingController::class, 'agentToken']);

    // 2FA verification (user has partial auth)
    Route::post('/2fa/verify', [TwoFactorController::class, 'verify']);
});

/*
|--------------------------------------------------------------------------
| Protected Routes (JWT Authentication Required)
|--------------------------------------------------------------------------
|
| Route organization by role requirement:
|   - Viewer (any authenticated): view devices, telemetry, alerts
|   - Operator (or admin): execute commands, manage devices, ack alerts
|   - Admin only: policy management, user management
|
*/
Route::middleware(['api', 'jwt.auth'])->group(function (): void {
    // Session management (all authenticated users)
    Route::post('/logout', [TokenController::class, 'logout']);

    // 2FA setup (all authenticated users can setup their own 2FA)
    Route::post('/2fa/setup', [TwoFactorController::class, 'setup']);
    Route::post('/2fa/confirm', [TwoFactorController::class, 'confirm']);

    /*
    |----------------------------------------------------------------------
    | Viewer Routes (Any Authenticated User)
    |----------------------------------------------------------------------
    | Read-only access to devices, telemetry, updates, alerts
    */
    Route::middleware('role:viewer')->group(function (): void {
        // Devices listing (read-only)
        Route::get('/devices', [DeviceController::class, 'index']);
        Route::get('/devices/unpaired', [DeviceController::class, 'unpaired']);
        Route::get('/devices/{device_id}', [DeviceController::class, 'show']);

        // Telemetry (read-only)
        Route::get('/devices/{device_id}/telemetry/latest', [TelemetryController::class, 'latest']);
        Route::get('/devices/{device_id}/telemetry/history', [TelemetryController::class, 'history']);

        // Updates info (read-only)
        Route::get('/devices/{device_id}/updates', [UpdateController::class, 'list']);
        Route::get('/devices/{device_id}/updates/{release_id}', [UpdateController::class, 'show']);

        // Audit trail (read-only)
        Route::get('/audit/device/{device_id}', [AuditTrailController::class, 'chain']);

        // Alerts listing (read-only)
        Route::get('/alerts', [AlertsController::class, 'index']);

        // Command status (read-only)
        Route::get('/commands/{command_id}', [CommandQueryController::class, 'show']);
        Route::get('/devices/{device_id}/commands', [CommandQueryController::class, 'deviceCommands']);

        // Compliance profiles (read-only)
        Route::get('/compliance/profiles', [ComplianceController::class, 'profiles']);

        // Pairing (viewer can pair their own device)
        Route::post('/pair/init', [PairingController::class, 'init']);
        Route::post('/pair/confirm', [PairingController::class, 'confirm']);
        // Deprecated alias for legacy clients
        Route::post('/pair', [PairingController::class, 'confirm']);
    });

    /*
    |----------------------------------------------------------------------
    | Operator Routes (Operator or Admin)
    |----------------------------------------------------------------------
    | Execute commands, manage devices, acknowledge alerts
    */
    Route::middleware('role:operator')->group(function (): void {
        // Device management
        Route::post('/devices/{device_id}/claim', [DeviceController::class, 'claim']);
        Route::post('/devices/{device_id}/rename', [DeviceController::class, 'rename']);

        // Commands execution
        // Commands execution (Token Required)
        Route::middleware('jwt.auth')->post('/commands', [CommandController::class, 'store']);
        // Deprecated alias for legacy clients
        Route::middleware('jwt.auth')->post('/command', [CommandController::class, 'store']);

        // Alert acknowledgment
        Route::post('/alerts/{alert_id}/ack', [AlertsController::class, 'acknowledge']);

        // Compliance evaluation
        Route::post('/compliance/evaluate', [ComplianceController::class, 'evaluate']);

        // Audit Trail append
        Route::post('/audit/append', [AuditTrailController::class, 'append']);
    });

    /*
    |----------------------------------------------------------------------
    | Admin Routes (Admin Only)
    |----------------------------------------------------------------------
    | Policy management, user management, system configuration
    */
    Route::middleware('role:admin')->group(function (): void {
        // Policy Engine management
        Route::post('/policy/evaluate', [PolicyController::class, 'evaluate']);
        Route::post('/policy/validate_bundle', [PolicyController::class, 'validateBundle']);
    });
});
