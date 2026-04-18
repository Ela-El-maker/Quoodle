<?php

namespace App\Http\Controllers\Compliance;

use App\Http\Controllers\Controller;
use App\Models\Device;
use App\Models\PolicyProfile;
use App\Services\Audit\AuditEventFeedService;
use App\Services\Compliance\ComplianceChecker;
use App\Services\Compliance\ComplianceOverviewService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;
use Symfony\Component\HttpFoundation\StreamedResponse;

class ComplianceController extends Controller
{
    public function __construct(
        private readonly ComplianceChecker $complianceChecker,
        private readonly ComplianceOverviewService $overview,
        private readonly AuditEventFeedService $auditFeed,
    )
    {
    }

    public function profiles(): JsonResponse
    {
        $profiles = PolicyProfile::all(['profile_id', 'description', 'rules'])->map(function ($p) {
            return [
                'profile_id' => $p->profile_id,
                'description' => $p->description,
                'rules' => $p->rules ?? [],
            ];
        });

        return response()->json([
            'profiles' => $profiles,
        ]);
    }

    public function evaluate(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'agent_version' => ['required', 'string'],
            'attestation_status' => ['required', 'string'],
            'device_id' => ['required', 'string'],
            'last_update_state' => ['required', 'string'],
            'os_build' => ['required', 'string'],
            'policy_hash' => ['required', 'string'],
            'profile_id' => ['required', 'string'],
            'revocation_status' => ['nullable', 'string'],
            'clock_skew_seconds' => ['nullable', 'integer'],
        ]);

        if ($validator->fails()) {
            return response()->json([
                'status' => 'unknown',
                'reasons' => $validator->errors()->all(),
            ], 422);
        }

        $data = $validator->validated();
        $device = Device::find($data['device_id']);
        if (! $device) {
            return response()->json(['status' => 'unknown_device'], 404);
        }

        $result = $this->complianceChecker->evaluateDevice($device, [
            'attestation_status' => $data['attestation_status'],
            'last_update_state' => $data['last_update_state'],
            'policy_hash' => $data['policy_hash'],
            'expected_policy_hash' => $device->policy_hash,
            'revocation_status' => $data['revocation_status'] ?? 'ok',
            'clock_skew_seconds' => $data['clock_skew_seconds'] ?? 0,
        ]);

        $device->update([
            'compliance_status' => $result['status'],
            'risk_score' => $device->risk_score,
        ]);

        return response()->json($result);
    }

    public function overview(Request $request): JsonResponse
    {
        return response()->json($this->overview->overview($request));
    }

    public function audit(Request $request): JsonResponse
    {
        $overrides = [
            'compliance_only' => true,
            'page' => max(1, (int) $request->query('page', 1)),
            'per_page' => min(max((int) $request->query('per_page', (int) $request->query('limit', 50)), 1), 200),
        ];

        return response()->json($this->auditFeed->list($request, $overrides));
    }

    public function export(Request $request): StreamedResponse
    {
        $format = strtolower(trim((string) $request->query('format', 'csv')));
        $fields = $this->selectedFields((string) $request->query('fields', ''));
        $overview = $this->overview->overview($request);
        $checks = $overview['checks'] ?? [];
        $dateToken = now('UTC')->format('Ymd-His');

        if ($format === 'pdf') {
            $lines = [];
            $lines[] = 'Compliance Report';
            $lines[] = 'Generated: '.now('UTC')->toIso8601String();
            $lines[] = 'Last Scan: '.(string) ($overview['last_scan_at'] ?? '');
            $lines[] = '';

            foreach ($checks as $check) {
                $parts = [];
                foreach ($fields as $field) {
                    $parts[] = strtoupper($field).': '.(string) ($check[$field] ?? '');
                }
                $lines[] = implode(' | ', $parts);
            }
            if ($checks === []) {
                $lines[] = 'No checks available.';
            }
            $content = implode("\n", $lines)."\n";

            return response()->streamDownload(function () use ($content): void {
                echo $content;
            }, "compliance-report-{$dateToken}.pdf", [
                'Content-Type' => 'application/pdf',
            ]);
        }

        return response()->streamDownload(function () use ($checks, $fields): void {
            $out = fopen('php://output', 'w');
            if (! $out) {
                return;
            }

            fputcsv($out, $fields);
            foreach ($checks as $check) {
                $row = [];
                foreach ($fields as $field) {
                    $row[] = $check[$field] ?? '';
                }
                fputcsv($out, $row);
            }
            fclose($out);
        }, "compliance-report-{$dateToken}.csv", [
            'Content-Type' => 'text/csv; charset=UTF-8',
        ]);
    }

    /**
     * @return array<int, string>
     */
    private function selectedFields(string $rawFields): array
    {
        $allowed = ['id', 'category', 'control', 'description', 'status', 'affected_devices', 'last_checked', 'severity'];
        $requested = array_values(array_filter(array_map('trim', explode(',', $rawFields))));
        if ($requested === []) {
            return $allowed;
        }

        $fields = array_values(array_intersect($requested, $allowed));

        return $fields === [] ? $allowed : $fields;
    }
}
