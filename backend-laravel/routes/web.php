<?php

use App\Http\Controllers\Auth\JWKSController;
use Illuminate\Support\Facades\Route;

Route::get('/', function () {
    return view('welcome');
});

Route::get('/.well-known/jwks.json', [JWKSController::class, 'show'])->name('jwks');
