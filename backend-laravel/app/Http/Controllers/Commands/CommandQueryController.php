<?php

namespace App\Http\Controllers\Commands;

use App\Http\Controllers\Controller;
use App\Models\Command;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class CommandQueryController extends Controller
{
    public function show(string $command_id): JsonResponse
    {
        $command = Command::find($command_id);
        if (! $command) {
            return response()->json(['message' => 'not_found'], 404);
        }

        return response()->json($this->formatCommand($command));
    }

    public function deviceCommands(Request $request, string $device_id): JsonResponse
    {
        $limit = (int) $request->query('limit', 20);
        $commands = Command::where('device_id', $device_id)
            ->orderByDesc('queued_at')
            ->limit($limit)
            ->get();

        return response()->json([
            'commands' => $commands->map(fn (Command $cmd) => [
                'command_id' => $cmd->id,
                'method' => $cmd->method,
                'state' => $cmd->state,
                'queued_at' => optional($cmd->queued_at)?->toIso8601String(),
                'completed_at' => optional($cmd->completed_at)?->toIso8601String(),
            ]),
            'next_before' => null,
        ]);
    }

    private function formatCommand(Command $cmd): array
    {
        $result = $cmd->result ?? [];

        return [
            'command_id' => $cmd->id,
            'device_id' => $cmd->device_id,
            'method' => $cmd->method,
            'params' => $cmd->params ?? [],
            'state' => $cmd->state,
            'queued_at' => optional($cmd->queued_at)?->toIso8601String(),
            'completed_at' => optional($cmd->completed_at)?->toIso8601String(),
            'result' => [
                'status' => $result['status'] ?? null,
                'notes' => $result['notes'] ?? null,
                'artifact_url' => $result['artifact_url'] ?? null,
                'artifact_checksum' => $result['artifact_checksum'] ?? null,
            ],
            'error_code' => $cmd->error_code,
            'error_message' => $cmd->error_message,
        ];
    }
}
