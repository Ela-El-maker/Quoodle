<?php

namespace App\Services\AI;

use Illuminate\Http\Client\RequestException;
use Illuminate\Support\Facades\Http;
use RuntimeException;

class AiSidecarClient
{
    /**
     * @param  array<string, mixed>  $payload
     * @return array<string, mixed>
     */
    public function ask(array $payload, string $correlationId): array
    {
        $baseUrl = rtrim((string) config('services.ai_sidecar.base_url', ''), '/');
        if ($baseUrl === '') {
            throw new RuntimeException('sidecar_not_configured');
        }

        $token = trim((string) config('services.ai_sidecar.service_token', ''));
        $timeout = (float) config('services.ai_sidecar.timeout_seconds', 15);

        $request = Http::acceptJson()
            ->timeout(max(1, $timeout))
            ->withHeaders([
                'X-Correlation-ID' => $correlationId,
            ]);

        if ($token !== '') {
            $request = $request->withToken($token);
        }

        try {
            $response = $request
                ->post($baseUrl.'/internal/ai/chat/ask', $payload)
                ->throw();
        } catch (RequestException $e) {
            $status = $e->response?->status();
            if ($status === 403) {
                throw new RuntimeException('sidecar_scope_unresolved', previous: $e);
            }
            if ($status === 422) {
                throw new RuntimeException('sidecar_validation_error', previous: $e);
            }

            throw new RuntimeException('sidecar_unavailable', previous: $e);
        } catch (\Throwable $e) {
            throw new RuntimeException('sidecar_unavailable', previous: $e);
        }

        $json = $response->json();
        if (! is_array($json)) {
            throw new RuntimeException('sidecar_invalid_response');
        }

        return $json;
    }
}

