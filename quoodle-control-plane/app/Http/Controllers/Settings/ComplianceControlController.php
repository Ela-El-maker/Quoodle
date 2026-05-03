<?php

namespace App\Http\Controllers\Settings;

use App\Http\Controllers\Controller;
use App\Models\SettingComplianceControl;
use App\Services\Settings\SettingsAuditService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\Rule;

final class ComplianceControlController extends Controller
{
    public function __construct(private readonly SettingsAuditService $audit)
    {
    }

    public function index(): JsonResponse
    {
        $controls = SettingComplianceControl::query()
            ->orderBy('sort_order')
            ->orderBy('check_id')
            ->get();

        return response()->json([
            'controls' => $controls->map(fn (SettingComplianceControl $control) => $this->serialize($control)),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'check_id' => ['required', 'string', 'max:32', 'unique:setting_compliance_controls,check_id'],
            'evaluator' => ['required', 'string', 'max:64'],
            'category' => ['required', 'string', 'max:190'],
            'control' => ['required', 'string', 'max:190'],
            'description' => ['required', 'string'],
            'severity' => ['required', Rule::in(['critical', 'warning', 'info'])],
            'failure_status' => ['required', Rule::in(['non_compliant', 'drift', 'pending'])],
            'enabled' => ['nullable', 'boolean'],
            'sort_order' => ['nullable', 'integer', 'min:0', 'max:65535'],
        ]);

        if ($validator->fails()) {
            return response()->json(['message' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $data = $validator->validated();
        $user = $request->user();

        $control = SettingComplianceControl::query()->create([
            ...$data,
            'enabled' => (bool) ($data['enabled'] ?? true),
            'sort_order' => (int) ($data['sort_order'] ?? 100),
            'created_by' => $user?->id,
            'updated_by' => $user?->id,
        ]);

        $after = $this->serialize($control);
        $this->audit->record(
            $user,
            'setting_compliance_control',
            (string) $control->id,
            'create',
            null,
            $after,
        );

        return response()->json(['control' => $after], 201);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $control = SettingComplianceControl::query()->find($id);
        if (! $control) {
            return response()->json(['message' => 'not_found'], 404);
        }

        $validator = Validator::make($request->all(), [
            'check_id' => [
                'sometimes',
                'required',
                'string',
                'max:32',
                Rule::unique('setting_compliance_controls', 'check_id')->ignore($control->id, 'id'),
            ],
            'evaluator' => ['sometimes', 'required', 'string', 'max:64'],
            'category' => ['sometimes', 'required', 'string', 'max:190'],
            'control' => ['sometimes', 'required', 'string', 'max:190'],
            'description' => ['sometimes', 'required', 'string'],
            'severity' => ['sometimes', 'required', Rule::in(['critical', 'warning', 'info'])],
            'failure_status' => ['sometimes', 'required', Rule::in(['non_compliant', 'drift', 'pending'])],
            'enabled' => ['sometimes', 'boolean'],
            'sort_order' => ['sometimes', 'integer', 'min:0', 'max:65535'],
        ]);

        if ($validator->fails()) {
            return response()->json(['message' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $before = $this->serialize($control);
        $data = $validator->validated();
        $user = $request->user();

        $control->fill($data);
        $control->updated_by = $user?->id;
        $control->save();

        $after = $this->serialize($control->fresh());
        $this->audit->record(
            $user,
            'setting_compliance_control',
            (string) $control->id,
            'update',
            $before,
            $after,
        );

        return response()->json(['control' => $after]);
    }

    public function destroy(Request $request, string $id): JsonResponse
    {
        $control = SettingComplianceControl::query()->find($id);
        if (! $control) {
            return response()->json(['message' => 'not_found'], 404);
        }

        $before = $this->serialize($control);
        $control->delete();

        $this->audit->record(
            $request->user(),
            'setting_compliance_control',
            $id,
            'delete',
            $before,
            null,
        );

        return response()->json(['status' => 'ok']);
    }

    /**
     * @return array<string, mixed>
     */
    private function serialize(SettingComplianceControl $control): array
    {
        return [
            'id' => $control->id,
            'check_id' => $control->check_id,
            'evaluator' => $control->evaluator,
            'category' => $control->category,
            'control' => $control->control,
            'description' => $control->description,
            'severity' => $control->severity,
            'failure_status' => $control->failure_status,
            'enabled' => (bool) $control->enabled,
            'sort_order' => (int) $control->sort_order,
            'created_at' => $control->created_at?->toIso8601String(),
            'updated_at' => $control->updated_at?->toIso8601String(),
        ];
    }
}
