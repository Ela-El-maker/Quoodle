<?php

use App\Http\Controllers\Webhooks\CommandResultWebhookController;
use Illuminate\Support\Facades\Route;

Route::prefix('api/v1/webhook')->group(function (): void {
    Route::post('/command/result', [CommandResultWebhookController::class, 'store']);
});
