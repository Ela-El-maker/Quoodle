<?php

namespace App\Http\Controllers\Settings;

use App\Http\Controllers\Controller;
use App\Models\SettingAlertRule;
use App\Services\Settings\SettingsAuditService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\Rule;

final class AlertRuleController extends Controller
{
    public function __construct(private readonly SettingsAuditService $audit)
    {
    }

    public function index(): JsonResponse
    {
        $rules = SettingAlertRule::query()
            ->orderByDesc('updated_at')
            ->get();

        return response()->json([
            'rules' => $rules->map(fn (SettingAlertRule $rule) => $this->serialize($rule)),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'name' => ['required', 'string', 'max:190'],
            'condition' => ['required', 'string'],
            'severity' => ['required', Rule::in(['critical', 'warning', 'info'])],
            'channels' => ['nullable', 'array'],
            'channels.*' => ['string', 'max:64'],
            'enabled' => ['nullable', 'boolean'],
        ]);

        if ($validator->fails()) {
            return response()->json(['message' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $data = $validator->validated();
        $user = $request->user();

        $rule = SettingAlertRule::query()->create([
            'name' => $data['name'],
            'condition' => $data['condition'],
            'severity' => $data['severity'],
            'channels' => $data['channels'] ?? [],
            'enabled' => (bool) ($data['enabled'] ?? true),
            'created_by' => $user?->id,
            'updated_by' => $user?->id,
        ]);

        $this->audit->record(
            $user,
            'setting_alert_rule',
            (string) $rule->id,
            'create',
            null,
            $this->serialize($rule),
        );

        return response()->json(['rule' => $this->serialize($rule)], 201);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $rule = SettingAlertRule::query()->find($id);
        if (! $rule) {
            return response()->json(['message' => 'not_found'], 404);
        }

        $validator = Validator::make($request->all(), [
            'name' => ['sometimes', 'required', 'string', 'max:190'],
            'condition' => ['sometimes', 'required', 'string'],
            'severity' => ['sometimes', 'required', Rule::in(['critical', 'warning', 'info'])],
            'channels' => ['sometimes', 'nullable', 'array'],
            'channels.*' => ['string', 'max:64'],
            'enabled' => ['sometimes', 'boolean'],
        ]);

        if ($validator->fails()) {
            return response()->json(['message' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $before = $this->serialize($rule);
        $data = $validator->validated();
        $user = $request->user();

        $rule->fill($data);
        $rule->updated_by = $user?->id;
        $rule->save();

        $after = $this->serialize($rule->fresh());
        $this->audit->record(
            $user,
            'setting_alert_rule',
            (string) $rule->id,
            'update',
            $before,
            $after,
        );

        return response()->json(['rule' => $after]);
    }

    public function destroy(Request $request, string $id): JsonResponse
    {
        $rule = SettingAlertRule::query()->find($id);
        if (! $rule) {
            return response()->json(['message' => 'not_found'], 404);
        }

        $before = $this->serialize($rule);
        $rule->delete();

        $this->audit->record(
            $request->user(),
            'setting_alert_rule',
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
    private function serialize(SettingAlertRule $rule): array
    {
        return [
            'id' => $rule->id,
            'name' => $rule->name,
            'condition' => $rule->condition,
            'severity' => $rule->severity,
            'channels' => is_array($rule->channels) ? $rule->channels : [],
            'enabled' => (bool) $rule->enabled,
            'created_at' => $rule->created_at?->toIso8601String(),
            'updated_at' => $rule->updated_at?->toIso8601String(),
        ];
    }
}

