<?php

namespace App\Http\Controllers\AI;

use App\Http\Controllers\Controller;
use App\Services\AI\DeviceHealthCopilotService;
use Illuminate\Auth\Access\AuthorizationException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;
use Illuminate\Support\Str;
use RuntimeException;

class CopilotController extends Controller
{
    public function __construct(private readonly DeviceHealthCopilotService $copilotService)
    {
    }

    public function ask(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'conversation_id' => ['nullable', 'string', 'max:64'],
            'query' => ['required', 'string', 'max:5000'],
            'selected_refs' => ['required', 'array'],
            'selected_refs.device_id' => ['required', 'string', 'max:190'],
            'ui_surface' => ['nullable', 'string', 'max:128'],
        ]);

        if ($validator->fails()) {
            return response()->json([
                'message' => 'invalid',
                'errors' => $validator->errors(),
            ], 422);
        }

        $user = $request->user();
        if (! $user) {
            return response()->json(['message' => 'unauthenticated'], 401);
        }

        $correlationId = trim((string) $request->header('X-Correlation-ID', ''));
        if ($correlationId === '') {
            $correlationId = 'corr_'.(string) Str::ulid();
        }

        try {
            $result = $this->copilotService->ask(
                user: $user,
                input: $validator->validated(),
                correlationId: $correlationId,
            );
        } catch (AuthorizationException) {
            return response()->json([
                'message' => 'forbidden',
                'correlation_id' => $correlationId,
            ], 403);
        } catch (RuntimeException $e) {
            $code = $e->getMessage();
            if ($code === 'ai_disabled') {
                return response()->json([
                    'message' => 'ai_disabled',
                    'correlation_id' => $correlationId,
                ], 503);
            }

            if (in_array($code, ['sidecar_scope_unresolved', 'invalid_request', 'sidecar_validation_error'], true)) {
                return response()->json([
                    'message' => 'invalid',
                    'code' => $code,
                    'correlation_id' => $correlationId,
                ], 422);
            }

            if (in_array($code, ['sidecar_unavailable', 'sidecar_not_configured', 'sidecar_invalid_response'], true)) {
                return response()->json([
                    'message' => 'copilot_unavailable',
                    'code' => $code,
                    'correlation_id' => $correlationId,
                ], 503);
            }

            report($e);

            return response()->json([
                'message' => 'copilot_failed',
                'code' => $code,
                'correlation_id' => $correlationId,
            ], 500);
        } catch (\Throwable $e) {
            report($e);

            return response()->json([
                'message' => 'copilot_failed',
                'correlation_id' => $correlationId,
            ], 500);
        }

        return response()->json($result);
    }

    public function conversation(Request $request, string $conversationId): JsonResponse
    {
        $user = $request->user();
        if (! $user) {
            return response()->json(['message' => 'unauthenticated'], 401);
        }

        try {
            $result = $this->copilotService->getConversation($user, $conversationId);
        } catch (AuthorizationException) {
            return response()->json(['message' => 'forbidden'], 403);
        } catch (RuntimeException $e) {
            if ($e->getMessage() === 'conversation_not_found') {
                return response()->json(['message' => 'not_found'], 404);
            }

            report($e);

            return response()->json([
                'message' => 'copilot_failed',
                'code' => $e->getMessage(),
            ], 500);
        } catch (\Throwable $e) {
            report($e);

            return response()->json(['message' => 'copilot_failed'], 500);
        }

        return response()->json($result);
    }
}
