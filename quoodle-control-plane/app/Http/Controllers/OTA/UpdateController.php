<?php

namespace App\Http\Controllers\OTA;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

class UpdateController extends Controller
{
    public function createRelease(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'release_id' => ['required', 'string'],
            'version' => ['required', 'string'],
            'manifest_url' => ['required', 'string'],
            'signature_url' => ['required', 'string'],
            'sha256' => ['required', 'string'],
        ]);

        if ($validator->fails()) {
            return response()->json(['status' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        return response()->json(['status' => 'created']);
    }
}
