<?php

namespace App\Http\Controllers\Settings;

use App\Http\Controllers\Controller;
use App\Models\SettingComplianceThreshold;
use App\Services\Settings\SettingsAuditService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\Rule;

final class ComplianceThresholdController extends Controller
{
    public function __construct(private readonly SettingsAuditService $audit)
    {
    }

    public function index(): JsonResponse
    {
        $thresholds = SettingComplianceThreshold::query()
            ->orderBy('control')
            ->orderBy('metric')
            ->get();

        return response()->json([
            'thresholds' => $thresholds->map(fn (SettingComplianceThreshold $threshold) => $this->serialize($threshold)),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'control' => ['required', 'string', 'max:190'],
            'metric' => ['required', 'string', 'max:190'],
            'threshold' => ['required', 'numeric'],
            'unit' => ['nullable', 'string', 'max:32'],
            'severity' => ['required', Rule::in(['critical', 'warning'])],
            'enabled' => ['nullable', 'boolean'],
        ]);

        if ($validator->fails()) {
            return response()->json(['message' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $data = $validator->validated();
        $user = $request->user();

        $threshold = SettingComplianceThreshold::query()->create([
            ...$data,
            'enabled' => (bool) ($data['enabled'] ?? true),
            'created_by' => $user?->id,
            'updated_by' => $user?->id,
        ]);

        $after = $this->serialize($threshold);
        $this->audit->record(
            $user,
            'setting_compliance_threshold',
            (string) $threshold->id,
            'create',
            null,
            $after,
        );

        return response()->json(['threshold' => $after], 201);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $threshold = SettingComplianceThreshold::query()->find($id);
        if (! $threshold) {
            return response()->json(['message' => 'not_found'], 404);
        }

        $validator = Validator::make($request->all(), [
            'control' => ['sometimes', 'required', 'string', 'max:190'],
            'metric' => ['sometimes', 'required', 'string', 'max:190'],
            'threshold' => ['sometimes', 'required', 'numeric'],
            'unit' => ['sometimes', 'nullable', 'string', 'max:32'],
            'severity' => ['sometimes', 'required', Rule::in(['critical', 'warning'])],
            'enabled' => ['sometimes', 'boolean'],
        ]);

        if ($validator->fails()) {
            return response()->json(['message' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $before = $this->serialize($threshold);
        $user = $request->user();
        $data = $validator->validated();
        $threshold->fill($data);
        $threshold->updated_by = $user?->id;
        $threshold->save();

        $after = $this->serialize($threshold->fresh());
        $this->audit->record(
            $user,
            'setting_compliance_threshold',
            (string) $threshold->id,
            'update',
            $before,
            $after,
        );

        return response()->json(['threshold' => $after]);
    }

    public function destroy(Request $request, string $id): JsonResponse
    {
        $threshold = SettingComplianceThreshold::query()->find($id);
        if (! $threshold) {
            return response()->json(['message' => 'not_found'], 404);
        }

        $before = $this->serialize($threshold);
        $threshold->delete();

        $this->audit->record(
            $request->user(),
            'setting_compliance_threshold',
            $id,
            'delete',
            $before,
            null,
        );

        return response()->json(['status' => 'ok']);
    }

    /**
     * @return array<string,mixed>
     */
    private function serialize(SettingComplianceThreshold $threshold): array
    {
        return [
            'id' => $threshold->id,
            'control' => $threshold->control,
            'metric' => $threshold->metric,
            'threshold' => $threshold->threshold,
            'unit' => $threshold->unit,
            'severity' => $threshold->severity,
            'enabled' => (bool) $threshold->enabled,
            'created_at' => $threshold->created_at?->toIso8601String(),
            'updated_at' => $threshold->updated_at?->toIso8601String(),
        ];
    }
}

