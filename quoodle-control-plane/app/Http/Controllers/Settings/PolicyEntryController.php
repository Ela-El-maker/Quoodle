<?php

namespace App\Http\Controllers\Settings;

use App\Http\Controllers\Controller;
use App\Models\SettingPolicyEntry;
use App\Services\Settings\SettingsAuditService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;

final class PolicyEntryController extends Controller
{
    public function __construct(private readonly SettingsAuditService $audit)
    {
    }

    public function index(Request $request): JsonResponse
    {
        $scope = trim((string) $request->query('scope', ''));
        $query = SettingPolicyEntry::query()->orderBy('policy_key');
        if ($scope !== '') {
            $query->where('scope', $scope);
        }

        $entries = $query->get();

        return response()->json([
            'entries' => $entries->map(fn (SettingPolicyEntry $entry) => $this->serialize($entry)),
        ]);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $entry = SettingPolicyEntry::query()->find($id);
        if (! $entry) {
            return response()->json(['message' => 'not_found'], 404);
        }

        $validator = Validator::make($request->all(), [
            'policy_value' => ['sometimes', 'nullable', 'string'],
            'description' => ['sometimes', 'nullable', 'string'],
            'scope' => ['sometimes', 'required', 'string', 'max:64'],
            'value_type' => ['sometimes', 'required', 'string', 'max:32'],
            'is_mutable' => ['sometimes', 'boolean'],
        ]);

        if ($validator->fails()) {
            return response()->json(['message' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $before = $this->serialize($entry);
        $data = $validator->validated();
        $user = $request->user();

        if (! $entry->is_mutable && array_key_exists('policy_value', $data)) {
            $next = (string) ($data['policy_value'] ?? '');
            $current = (string) ($entry->policy_value ?? '');
            if ($next !== $current) {
                return response()->json(['message' => 'immutable_policy_entry'], 409);
            }
        }

        $entry->fill($data);
        $entry->updated_by = $user?->id;
        $entry->save();

        $after = $this->serialize($entry->fresh());
        $this->audit->record(
            $user,
            'setting_policy_entry',
            (string) $entry->id,
            'update',
            $before,
            $after,
        );

        return response()->json(['entry' => $after]);
    }

    /**
     * @return array<string,mixed>
     */
    private function serialize(SettingPolicyEntry $entry): array
    {
        return [
            'id' => $entry->id,
            'policy_key' => $entry->policy_key,
            'policy_value' => $entry->policy_value,
            'scope' => $entry->scope,
            'value_type' => $entry->value_type,
            'description' => $entry->description,
            'is_mutable' => (bool) $entry->is_mutable,
            'created_at' => $entry->created_at?->toIso8601String(),
            'updated_at' => $entry->updated_at?->toIso8601String(),
        ];
    }
}

