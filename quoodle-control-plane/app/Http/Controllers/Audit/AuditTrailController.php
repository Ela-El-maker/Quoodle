<?php

namespace App\Http\Controllers\Audit;

use App\Http\Controllers\Controller;
use App\Models\AuditTrail;
use App\Services\Audit\AuditEventFeedService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;
use Symfony\Component\HttpFoundation\StreamedResponse;

class AuditTrailController extends Controller
{
    public function __construct(private readonly AuditEventFeedService $feed)
    {
    }

    public function append(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'actor' => ['required', 'string'],
            'actor_id' => ['required', 'string'],
            'audit_id' => ['required', 'string'],
            'device_id' => ['nullable', 'string'],
            'event_type' => ['required', 'string'],
            'payload_hash' => ['required', 'string'],
            'prev_hash' => ['nullable', 'string'],
            'signature' => ['required', 'string'],
            'timestamp' => ['required', 'string'],
        ]);

        if ($validator->fails()) {
            return response()->json([
                'status' => 'invalid',
                'errors' => $validator->errors()->all(),
            ], 422);
        }

        $data = $validator->validated();

        $latest = AuditTrail::where('device_id', $data['device_id'])
            ->orderBy('timestamp', 'desc')
            ->first();
        $prevHash = $data['prev_hash'] ?? ($latest->hash ?? null);
        $computedHash = hash('sha256', ($prevHash ?? '') . $data['payload_hash']);

        $entry = AuditTrail::create([
            'audit_id' => $data['audit_id'],
            'actor' => $data['actor'],
            'actor_id' => $data['actor_id'],
            'device_id' => $data['device_id'],
            'event_type' => $data['event_type'],
            'payload_hash' => $data['payload_hash'],
            'prev_hash' => $prevHash,
            'hash' => $computedHash,
            'signature' => $data['signature'],
            'timestamp' => $data['timestamp'],
        ]);

        return response()->json([
            'status' => 'ok',
            'stored_hash' => $entry->hash,
        ]);
    }

    public function chain(Request $request, string $device_id): JsonResponse
    {
        $limit = min((int) ($request->query('limit') ?? 500), 1000);
        $entries = AuditTrail::where('device_id', $device_id)
            ->orderBy('timestamp')
            ->limit($limit)
            ->get();

        return response()->json([
            'entries' => $entries->map(function (AuditTrail $entry) {
                return [
                    'id' => $entry->audit_id,
                    'timestamp' => optional($entry->timestamp)?->toIso8601String(),
                    'event_type' => $entry->event_type,
                    'summary' => $entry->event_type.' event',
                    'details' => [
                        'hash' => $entry->hash,
                        'prev_hash' => $entry->prev_hash,
                        'signature' => $entry->signature,
                    ],
                ];
            }),
        ]);
    }

    public function events(Request $request): JsonResponse
    {
        return response()->json($this->feed->list($request));
    }

    public function export(Request $request): StreamedResponse
    {
        $format = strtolower(trim((string) $request->query('format', 'csv')));
        $payload = $this->feed->list($request, [
            'for_export' => true,
            'export_limit' => min(max((int) $request->query('limit', 5000), 1), 10000),
            'page' => 1,
            'per_page' => 10000,
        ]);

        $events = $payload['events'] ?? [];
        $fields = $this->selectedFields((string) $request->query('fields', ''));
        $dateToken = now('UTC')->format('Ymd-His');

        if ($format === 'pdf') {
            $lines = [];
            $lines[] = 'Audit Events Report';
            $lines[] = 'Generated: '.now('UTC')->toIso8601String();
            $lines[] = '';
            foreach ($events as $event) {
                $segments = [];
                foreach ($fields as $field) {
                    $segments[] = strtoupper($field).': '.(string) ($event[$field] ?? '');
                }
                $lines[] = implode(' | ', $segments);
            }
            if ($events === []) {
                $lines[] = 'No matching events.';
            }
            $content = implode("\n", $lines)."\n";

            return response()->streamDownload(function () use ($content): void {
                echo $content;
            }, "audit-events-{$dateToken}.pdf", [
                'Content-Type' => 'application/pdf',
            ]);
        }

        return response()->streamDownload(function () use ($events, $fields): void {
            $out = fopen('php://output', 'w');
            if (! $out) {
                return;
            }

            fputcsv($out, $fields);
            foreach ($events as $event) {
                $row = [];
                foreach ($fields as $field) {
                    $row[] = $event[$field] ?? '';
                }
                fputcsv($out, $row);
            }
            fclose($out);
        }, "audit-events-{$dateToken}.csv", [
            'Content-Type' => 'text/csv; charset=UTF-8',
        ]);
    }

    /**
     * @return array<int, string>
     */
    private function selectedFields(string $rawFields): array
    {
        $allowed = ['id', 'timestamp', 'actor', 'actor_role', 'event_type', 'action', 'target', 'detail', 'outcome', 'source'];
        $requested = array_values(array_filter(array_map('trim', explode(',', $rawFields))));
        if ($requested === []) {
            return $allowed;
        }

        $fields = array_values(array_intersect($requested, $allowed));

        return $fields === [] ? $allowed : $fields;
    }
}
