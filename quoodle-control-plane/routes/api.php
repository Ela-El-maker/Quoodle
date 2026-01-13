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

Route::middleware('api')->group(function (): void {
    // Auth & tokens
    Route::post('/register', [RegisterController::class, 'register']);
    Route::post('/login', [LoginController::class, 'login']);
    Route::post('/2fa/setup', [TwoFactorController::class, 'setup']);
    Route::post('/2fa/confirm', [TwoFactorController::class, 'confirm']);
    Route::post('/2fa/verify', [TwoFactorController::class, 'verify']);
    Route::post('/token/refresh', [TokenController::class, 'refresh']);
    Route::post('/logout', [TokenController::class, 'logout']);

    // Devices & pairing
    Route::get('/devices', [DeviceController::class, 'index']);
    Route::get('/devices/unpaired', [DeviceController::class, 'unpaired']);
    Route::post('/devices/{device_id}/claim', [DeviceController::class, 'claim']);
    Route::get('/devices/{device_id}', [DeviceController::class, 'show']);
    Route::post('/devices/{device_id}/rename', [DeviceController::class, 'rename']);
    Route::post('/pair/init', [PairingController::class, 'init']);
    Route::post('/pair/confirm', [PairingController::class, 'confirm']);

    // Commands
    Route::post('/commands', [CommandController::class, 'store']);
    Route::get('/commands/{command_id}', [CommandQueryController::class, 'show']);
    Route::get('/devices/{device_id}/commands', [CommandQueryController::class, 'deviceCommands']);

    // Telemetry
    Route::get('/devices/{device_id}/telemetry/latest', [TelemetryController::class, 'latest']);
    Route::get('/devices/{device_id}/telemetry/history', [TelemetryController::class, 'history']);

    // Updates
    Route::get('/devices/{device_id}/updates', [UpdateController::class, 'list']);
    Route::get('/devices/{device_id}/updates/{release_id}', [UpdateController::class, 'show']);

    // Audit & alerts
    Route::get('/audit/device/{device_id}', [AuditTrailController::class, 'chain']);
    Route::get('/alerts', [AlertsController::class, 'index']);
    Route::post('/alerts/{alert_id}/ack', [AlertsController::class, 'acknowledge']);

    // Policy Engine
    Route::post('/policy/evaluate', [PolicyController::class, 'evaluate']);
    Route::post('/policy/validate_bundle', [PolicyController::class, 'validateBundle']);

    // Compliance Engine
    Route::get('/compliance/profiles', [ComplianceController::class, 'profiles']);
    Route::post('/compliance/evaluate', [ComplianceController::class, 'evaluate']);

    // Audit Trail append
    Route::post('/audit/append', [AuditTrailController::class, 'append']);
});
