<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use App\Services\JWT\JWKSManager;
use Illuminate\Http\JsonResponse;

class JWKSController extends Controller
{
    public function __construct(private readonly JWKSManager $jwksManager)
    {
    }

    public function show(): JsonResponse
    {
        return response()->json($this->jwksManager->keySet());
    }
}
