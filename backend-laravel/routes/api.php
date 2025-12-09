<?php

use App\Http\Controllers\Auth\LoginController;
use App\Http\Controllers\Auth\RegisterController;
use App\Http\Controllers\Commands\CommandController;
use App\Http\Controllers\Policy\PolicyController;
use App\Http\Controllers\Compliance\ComplianceController;
use App\Http\Controllers\Audit\AuditTrailController;
use Illuminate\Support\Facades\Route;

Route::middleware('api')->group(function (): void {
    Route::post('/auth/register', [RegisterController::class, 'register']);
    Route::post('/auth/login', [LoginController::class, 'login']);
    Route::post('/register', [RegisterController::class, 'register']);
    Route::post('/login', [LoginController::class, 'login']);
    Route::post('/commands', [CommandController::class, 'store']);

    // Policy Engine
    Route::post('/policy/evaluate', [PolicyController::class, 'evaluate']);
    Route::post('/policy/validate_bundle', [PolicyController::class, 'validateBundle']);

    // Compliance Engine
    Route::get('/compliance/profiles', [ComplianceController::class, 'profiles']);
    Route::post('/compliance/evaluate', [ComplianceController::class, 'evaluate']);

    // Audit Trail
    Route::post('/audit/append', [AuditTrailController::class, 'append']);
    Route::get('/audit/chain/{device_id}', [AuditTrailController::class, 'chain']);
});
