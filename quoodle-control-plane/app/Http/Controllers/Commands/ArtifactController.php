<?php

namespace App\Http\Controllers\Commands;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;

class ArtifactController extends Controller
{
    public function requestUpload(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'command_id' => ['required', 'string'],
            'content_type' => ['nullable', 'string'],
            'size_bytes' => ['nullable', 'integer'],
        ]);

        if ($validator->fails()) {
            return response()->json(['status' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $data = $validator->validated();
        $artifactId = (string) Str::uuid();
        $uploadToken = Str::random(40);
        $expiresAt = now()->addMinutes(10);

        Cache::put("artifact_upload:{$artifactId}", [
            'command_id' => $data['command_id'],
            'upload_token' => $uploadToken,
            'content_type' => $data['content_type'] ?? null,
            'size_bytes' => $data['size_bytes'] ?? null,
        ], $expiresAt);

        return response()->json([
            'status' => 'ok',
            'artifact_id' => $artifactId,
            'upload_url' => url('/api/artifact/upload'),
            'upload_token' => $uploadToken,
            'expires_at' => $expiresAt->toIso8601String(),
        ]);
    }

    public function upload(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'artifact_id' => ['required', 'string'],
            'upload_token' => ['required', 'string'],
            'artifact' => ['required', 'file'],
        ]);

        if ($validator->fails()) {
            return response()->json(['status' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $data = $validator->validated();
        $cache = Cache::get("artifact_upload:{$data['artifact_id']}");
        if (! is_array($cache) || ($cache['upload_token'] ?? null) !== $data['upload_token']) {
            return response()->json(['status' => 'invalid', 'reason' => 'upload_token_invalid'], 401);
        }

        $file = $request->file('artifact');
        $path = "artifacts/{$data['artifact_id']}";
        $contents = file_get_contents($file->getRealPath());
        Storage::disk('local')->put($path, $contents);
        $checksum = hash('sha256', $contents);
        Cache::forget("artifact_upload:{$data['artifact_id']}");

        return response()->json([
            'status' => 'stored',
            'artifact_id' => $data['artifact_id'],
            'artifact_url' => url('/api/artifact/'.$data['artifact_id']),
            'artifact_checksum' => $checksum,
        ]);
    }

    public function download(string $artifact_id)
    {
        $path = "artifacts/{$artifact_id}";
        if (! Storage::disk('local')->exists($path)) {
            return response()->json(['status' => 'not_found'], 404);
        }

        return Storage::disk('local')->download($path);
    }

    public function store(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'command_id' => ['required', 'string'],
            'artifact_url' => ['required', 'string'],
            'checksum' => ['required', 'string'],
        ]);

        if ($validator->fails()) {
            return response()->json(['status' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        return response()->json(['status' => 'stored']);
    }
}
