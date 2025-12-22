<?php

use App\Http\Controllers\Webhooks\AttestationWebhookController;
use App\Http\Controllers\Webhooks\CommandAckWebhookController;
use App\Http\Controllers\Webhooks\CommandResultWebhookController;
use App\Http\Controllers\Webhooks\DevicePresenceWebhookController;
use App\Http\Controllers\Webhooks\TelemetryWebhookController;
use Illuminate\Support\Facades\Route;

Route::prefix('api/v1/webhook')->middleware('fastapi.signature')->group(function (): void {
    Route::post('/device/online', [DevicePresenceWebhookController::class, 'online']);
    Route::post('/device/offline', [DevicePresenceWebhookController::class, 'offline']);
    Route::post('/command/result', [CommandResultWebhookController::class, 'store']);
    Route::post('/command/ack', [CommandAckWebhookController::class, 'store']);
    Route::post('/telemetry/summary', [TelemetryWebhookController::class, 'store']);
    Route::post('/security/attestation', [AttestationWebhookController::class, 'store']);
});
