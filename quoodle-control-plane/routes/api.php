<?php

use App\Http\Controllers\Auth\MeController;
use App\Http\Controllers\Auth\GoogleAuthController;
use App\Http\Controllers\Auth\OtpAuthController;
use App\Http\Controllers\Auth\SessionController;
use App\Http\Controllers\Auth\TokenController;
use App\Http\Controllers\Auth\TwoFactorController;
use App\Http\Controllers\Alerts\AlertsController;
use App\Http\Controllers\Commands\CommandController;
use App\Http\Controllers\Commands\CommandQueryController;
use App\Http\Controllers\Commands\ArtifactController;
use App\Http\Controllers\Devices\DeviceController;
use App\Http\Controllers\Devices\MobileDeviceController;
use App\Http\Controllers\Devices\PairingController;
use App\Http\Controllers\Policy\PolicyController;
use App\Http\Controllers\Compliance\ComplianceController;
use App\Http\Controllers\Audit\AuditTrailController;
use App\Http\Controllers\Telemetry\TelemetryController;
use App\Http\Controllers\Telemetry\TelemetryQueryController;
use App\Http\Controllers\Updates\UpdateController;
use App\Http\Controllers\Schedules\ScheduleController;
use App\Http\Controllers\Schedules\ScheduleRunsController;
use Illuminate\Support\Facades\Route;

/*
|--------------------------------------------------------------------------
| Public Routes (No Authentication Required)
|--------------------------------------------------------------------------
*/
Route::middleware('api')->group(function (): void {
    // Authentication endpoints (rate-limited to prevent brute force)
    Route::middleware('throttle:10,1')->group(function (): void {
        Route::post('/auth/request-otp', [OtpAuthController::class, 'requestOtp']);
        Route::post('/auth/verify-otp', [OtpAuthController::class, 'verifyOtp']);
        Route::post('/auth/google/exchange', [GoogleAuthController::class, 'exchange']);
        Route::post('/token/refresh', [TokenController::class, 'refresh']);
    });
    Route::post('/pair/request', [PairingController::class, 'request']);
    Route::post('/agent/token', [PairingController::class, 'agentToken']);
    // Agent artifact upload (device-scoped JWT)
    Route::middleware('agent.jwt')->group(function (): void {
        Route::post('/artifact/request', [ArtifactController::class, 'requestUpload']);
        Route::post('/artifact/upload', [ArtifactController::class, 'upload']);
    });

    // 2FA verification (user has partial auth)
    Route::post('/2fa/verify', [TwoFactorController::class, 'verify']);
});

/*
|--------------------------------------------------------------------------
| Protected Routes (JWT Authentication Required)
|--------------------------------------------------------------------------
|
| Route organization by role requirement:
|   - Viewer (any authenticated): view devices and telemetry
|   - Operator (or admin): execute commands, manage devices, ack alerts
|   - Admin only: policy management, user management
|
*/
Route::middleware(['api', 'jwt.auth'])->group(function (): void {
    Route::get('/me', MeController::class);

    // Session management (all authenticated users)
    Route::post('/logout', [TokenController::class, 'logout']);

    // 2FA setup (all authenticated users can setup their own 2FA)
    Route::post('/2fa/setup', [TwoFactorController::class, 'setup']);
    Route::post('/2fa/confirm', [TwoFactorController::class, 'confirm']);

    /*
    |----------------------------------------------------------------------
    | Viewer Routes (Any Authenticated User)
    |----------------------------------------------------------------------
    | Read-only access to devices, telemetry, updates
    */
    Route::middleware('role:viewer')->group(function (): void {
        // Devices listing (read-only)
        Route::get('/devices', [DeviceController::class, 'index']);
        Route::get('/devices/unpaired', [DeviceController::class, 'unpaired']);
        Route::get('/devices/{device_id}', [DeviceController::class, 'show']);

        // Mobile devices (read-only)
        Route::get('/mobile-devices', [MobileDeviceController::class, 'index']);

        // Telemetry (read-only)
        Route::get('/devices/{device_id}/telemetry/latest', [TelemetryController::class, 'latest']);
        Route::get('/devices/{device_id}/telemetry/history', [TelemetryController::class, 'history']);
        Route::get('/telemetry/devices/{device_id}/latest', [TelemetryQueryController::class, 'latest']);
        Route::get('/telemetry/devices/{device_id}/history', [TelemetryQueryController::class, 'history']);
        Route::get('/telemetry/fleet/summary', [TelemetryQueryController::class, 'fleetSummary']);
        Route::get('/telemetry/fleet/timeseries', [TelemetryQueryController::class, 'fleetTimeseries']);
        Route::get('/telemetry/activity', [TelemetryQueryController::class, 'activity']);
        Route::get('/telemetry/ops/health', [TelemetryQueryController::class, 'opsHealth']);

        // Updates info (read-only)
        Route::get('/devices/{device_id}/updates', [UpdateController::class, 'list']);
        Route::get('/devices/{device_id}/updates/{release_id}', [UpdateController::class, 'show']);

        // Artifact download (read-only)
        Route::get('/artifact/{artifact_id}', [ArtifactController::class, 'download']);

        // Audit trail (read-only)
        Route::get('/audit/device/{device_id}', [AuditTrailController::class, 'chain']);
        Route::get('/audit/events', [AuditTrailController::class, 'events']);
        Route::get('/audit/events/export', [AuditTrailController::class, 'export']);

        // Command status (read-only)
        Route::get('/commands', [CommandQueryController::class, 'index']);
        Route::get('/commands/capabilities', [CommandQueryController::class, 'capabilities']);
        Route::get('/commands/{command_id}', [CommandQueryController::class, 'show']);
        Route::get('/devices/{device_id}/commands', [CommandQueryController::class, 'deviceCommands']);

        // Compliance profiles (read-only)
        Route::get('/compliance/profiles', [ComplianceController::class, 'profiles']);
        Route::get('/compliance/overview', [ComplianceController::class, 'overview']);
        Route::get('/compliance/audit', [ComplianceController::class, 'audit']);
        Route::get('/compliance/export', [ComplianceController::class, 'export']);

        // Session update (push notifications)
        Route::post('/session/push-token', [SessionController::class, 'updatePushToken']);

        // Pairing (viewer can pair their own device)
        Route::post('/pair/init', [PairingController::class, 'init']);
        Route::get('/pair/session/{pair_session_id}', [PairingController::class, 'session']);
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

        // Device-scoped app lock policy (operators can manage their owned devices; admins can manage all)
        Route::get('/policy/app-lock', [PolicyController::class, 'appLockShow']);
        Route::put('/policy/app-lock', [PolicyController::class, 'appLockUpsert']);
        Route::delete('/policy/app-lock', [PolicyController::class, 'appLockClear']);

        // Alerts listing and acknowledgment
        Route::get('/alerts', [AlertsController::class, 'index']);

        // Commands execution
        // Commands execution (Token Required)
        Route::middleware('jwt.auth')->post('/commands', [CommandController::class, 'store']);
        // Deprecated alias for legacy clients
        Route::middleware('jwt.auth')->post('/command', [CommandController::class, 'store']);

        // Command scheduling
        Route::get('/schedules', [ScheduleController::class, 'index']);
        Route::post('/schedules', [ScheduleController::class, 'store']);
        Route::patch('/schedules/{schedule_id}', [ScheduleController::class, 'update']);
        Route::delete('/schedules/{schedule_id}', [ScheduleController::class, 'destroy']);
        Route::post('/schedules/{schedule_id}/run-now', [ScheduleController::class, 'runNow']);
        Route::get('/schedules/runs', [ScheduleRunsController::class, 'index']);

        Route::post('/alerts/{alert_id}/ack', [AlertsController::class, 'acknowledge']);

        // Compliance evaluation
        Route::post('/compliance/evaluate', [ComplianceController::class, 'evaluate']);

        // Policy evaluation (command preflight)
        Route::post('/policy/evaluate', [PolicyController::class, 'evaluate']);

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
        Route::post('/policy/validate_bundle', [PolicyController::class, 'validateBundle']);
    });
});
