<?php

namespace App\Http\Controllers\Settings;

use App\Http\Controllers\Controller;
use App\Models\Device;
use App\Models\TeamMemberDeviceAccess;
use App\Models\User;
use App\Services\Settings\SettingsAuditService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Validator;
use Illuminate\Validation\Rule;

final class TeamMemberController extends Controller
{
    public function __construct(private readonly SettingsAuditService $audit)
    {
    }

    public function index(): JsonResponse
    {
        $members = User::query()
            ->orderBy('display_name')
            ->get(['id', 'display_name', 'email', 'role', 'account_status', 'deactivated_at', 'created_at', 'updated_at']);

        $memberIds = $members->pluck('id')->all();
        $deviceAccess = TeamMemberDeviceAccess::query()
            ->whereIn('user_id', $memberIds)
            ->get(['user_id', 'device_id'])
            ->groupBy('user_id')
            ->map(fn ($rows) => $rows->pluck('device_id')->values()->all());

        $allDevices = Device::query()
            ->orderBy('device_name')
            ->get(['device_id', 'device_name', 'lifecycle_state', 'os_build']);

        return response()->json([
            'members' => $members->map(function (User $member) use ($deviceAccess): array {
                return [
                    'id' => $member->id,
                    'display_name' => $member->display_name,
                    'email' => $member->email,
                    'role' => $member->role,
                    'account_status' => (string) ($member->account_status ?? User::STATUS_ACTIVE),
                    'deactivated_at' => $member->deactivated_at?->toIso8601String(),
                    'created_at' => $member->created_at?->toIso8601String(),
                    'updated_at' => $member->updated_at?->toIso8601String(),
                    'device_access' => $deviceAccess->get($member->id, []),
                ];
            }),
            'devices' => $allDevices->map(fn (Device $device) => [
                'device_id' => $device->device_id,
                'device_name' => $device->device_name,
                'lifecycle_state' => $device->lifecycle_state,
                'os_build' => $device->os_build,
            ]),
        ]);
    }

    public function store(Request $request): JsonResponse
    {
        $validator = Validator::make($request->all(), [
            'display_name' => ['required', 'string', 'max:190'],
            'email' => ['required', 'email', 'max:190'],
            'role' => ['required', Rule::in(User::ROLES)],
            'account_status' => ['nullable', Rule::in([
                User::STATUS_ACTIVE,
                User::STATUS_INACTIVE,
                User::STATUS_PENDING,
            ])],
            'device_access' => ['nullable', 'array'],
            'device_access.*' => ['string', 'max:190'],
        ]);

        if ($validator->fails()) {
            return response()->json(['message' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $data = $validator->validated();
        $email = strtolower(trim((string) $data['email']));

        if (User::query()->whereRaw('LOWER(email) = ?', [$email])->exists()) {
            return response()->json(['message' => 'email_exists'], 409);
        }

        $user = $request->user();
        $accountStatus = (string) ($data['account_status'] ?? User::STATUS_PENDING);
        $member = User::query()->create([
            'display_name' => $data['display_name'],
            'email' => $email,
            'role' => $data['role'],
            'account_status' => $accountStatus,
            'deactivated_at' => $accountStatus === User::STATUS_INACTIVE ? now() : null,
            'invited_by' => $user?->id,
        ]);

        $access = $this->syncDeviceAccess($member, $data['device_access'] ?? [], $user?->id);

        $this->audit->record(
            $user,
            'team_member',
            (string) $member->id,
            'create',
            null,
            $this->serializeMember($member->fresh(), $access),
        );

        return response()->json([
            'member' => $this->serializeMember($member->fresh(), $access),
        ], 201);
    }

    public function update(Request $request, string $id): JsonResponse
    {
        $member = User::query()->find($id);
        if (! $member) {
            return response()->json(['message' => 'not_found'], 404);
        }

        $validator = Validator::make($request->all(), [
            'display_name' => ['sometimes', 'required', 'string', 'max:190'],
            'role' => ['sometimes', 'required', Rule::in(User::ROLES)],
            'account_status' => ['sometimes', 'required', Rule::in([
                User::STATUS_ACTIVE,
                User::STATUS_INACTIVE,
                User::STATUS_PENDING,
            ])],
            'device_access' => ['sometimes', 'array'],
            'device_access.*' => ['string', 'max:190'],
        ]);

        if ($validator->fails()) {
            return response()->json(['message' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $beforeAccess = TeamMemberDeviceAccess::query()
            ->where('user_id', $member->id)
            ->pluck('device_id')
            ->values()
            ->all();
        $before = $this->serializeMember($member, $beforeAccess);

        $data = $validator->validated();
        $user = $request->user();

        if (array_key_exists('display_name', $data)) {
            $member->display_name = (string) $data['display_name'];
        }
        if (array_key_exists('role', $data)) {
            $member->role = (string) $data['role'];
        }
        if (array_key_exists('account_status', $data)) {
            $member->account_status = (string) $data['account_status'];
            $member->deactivated_at = $member->account_status === User::STATUS_INACTIVE ? now() : null;
        }
        $member->save();

        $access = array_key_exists('device_access', $data)
            ? $this->syncDeviceAccess($member, $data['device_access'], $user?->id)
            : $beforeAccess;

        $after = $this->serializeMember($member->fresh(), $access);
        $this->audit->record(
            $user,
            'team_member',
            (string) $member->id,
            'update',
            $before,
            $after,
        );

        return response()->json(['member' => $after]);
    }

    public function activate(Request $request, string $id): JsonResponse
    {
        return $this->changeStatus($request, $id, User::STATUS_ACTIVE);
    }

    public function deactivate(Request $request, string $id): JsonResponse
    {
        return $this->changeStatus($request, $id, User::STATUS_INACTIVE);
    }

    public function listDeviceAccess(string $id): JsonResponse
    {
        $member = User::query()->find($id);
        if (! $member) {
            return response()->json(['message' => 'not_found'], 404);
        }

        $deviceIds = TeamMemberDeviceAccess::query()
            ->where('user_id', $id)
            ->pluck('device_id')
            ->values();

        $devices = Device::query()
            ->whereIn('device_id', $deviceIds)
            ->get(['device_id', 'device_name', 'lifecycle_state', 'os_build']);

        return response()->json([
            'user_id' => $id,
            'devices' => $devices,
        ]);
    }

    public function grantDeviceAccess(Request $request, string $id): JsonResponse
    {
        $member = User::query()->find($id);
        if (! $member) {
            return response()->json(['message' => 'not_found'], 404);
        }

        $validator = Validator::make($request->all(), [
            'device_id' => ['required', 'string', 'max:190', 'exists:devices,device_id'],
        ]);

        if ($validator->fails()) {
            return response()->json(['message' => 'invalid', 'errors' => $validator->errors()], 422);
        }

        $data = $validator->validated();
        $user = $request->user();

        TeamMemberDeviceAccess::query()->updateOrCreate(
            ['user_id' => $member->id, 'device_id' => $data['device_id']],
            ['granted_by' => $user?->id],
        );

        $access = TeamMemberDeviceAccess::query()
            ->where('user_id', $member->id)
            ->pluck('device_id')
            ->values()
            ->all();

        $this->audit->record(
            $user,
            'team_member_device_access',
            (string) $member->id,
            'grant',
            ['device_access' => $access],
            ['device_access' => $access],
            ['device_id' => $data['device_id']],
        );

        return response()->json([
            'user_id' => $member->id,
            'device_access' => $access,
        ]);
    }

    public function revokeDeviceAccess(Request $request, string $id, string $deviceId): JsonResponse
    {
        $member = User::query()->find($id);
        if (! $member) {
            return response()->json(['message' => 'not_found'], 404);
        }

        TeamMemberDeviceAccess::query()
            ->where('user_id', $member->id)
            ->where('device_id', $deviceId)
            ->delete();

        $access = TeamMemberDeviceAccess::query()
            ->where('user_id', $member->id)
            ->pluck('device_id')
            ->values()
            ->all();

        $this->audit->record(
            $request->user(),
            'team_member_device_access',
            (string) $member->id,
            'revoke',
            null,
            ['device_access' => $access],
            ['device_id' => $deviceId],
        );

        return response()->json([
            'user_id' => $member->id,
            'device_access' => $access,
        ]);
    }

    private function changeStatus(Request $request, string $id, string $status): JsonResponse
    {
        $member = User::query()->find($id);
        if (! $member) {
            return response()->json(['message' => 'not_found'], 404);
        }

        $currentAccess = TeamMemberDeviceAccess::query()
            ->where('user_id', $member->id)
            ->pluck('device_id')
            ->values()
            ->all();

        $before = $this->serializeMember($member, $currentAccess);
        $member->account_status = $status;
        $member->deactivated_at = $status === User::STATUS_INACTIVE ? now() : null;
        $member->save();

        $after = $this->serializeMember($member->fresh(), $currentAccess);
        $this->audit->record(
            $request->user(),
            'team_member',
            (string) $member->id,
            $status === User::STATUS_ACTIVE ? 'activate' : 'deactivate',
            $before,
            $after,
        );

        return response()->json(['member' => $after]);
    }

    /**
     * @param  array<int,string>  $deviceIds
     * @return array<int,string>
     */
    private function syncDeviceAccess(User $member, array $deviceIds, ?string $grantedBy): array
    {
        $normalized = collect($deviceIds)
            ->filter(fn ($id) => is_string($id) && trim($id) !== '')
            ->map(fn ($id) => trim((string) $id))
            ->unique()
            ->values();

        $validIds = Device::query()
            ->whereIn('device_id', $normalized->all())
            ->pluck('device_id')
            ->values()
            ->all();

        TeamMemberDeviceAccess::query()->where('user_id', $member->id)->delete();
        foreach ($validIds as $deviceId) {
            TeamMemberDeviceAccess::query()->create([
                'user_id' => $member->id,
                'device_id' => $deviceId,
                'granted_by' => $grantedBy,
            ]);
        }

        return $validIds;
    }

    /**
     * @param  array<int,string>  $deviceAccess
     * @return array<string,mixed>
     */
    private function serializeMember(User $member, array $deviceAccess): array
    {
        return [
            'id' => $member->id,
            'display_name' => $member->display_name,
            'email' => $member->email,
            'role' => $member->role,
            'account_status' => (string) ($member->account_status ?? User::STATUS_ACTIVE),
            'deactivated_at' => $member->deactivated_at?->toIso8601String(),
            'created_at' => $member->created_at?->toIso8601String(),
            'updated_at' => $member->updated_at?->toIso8601String(),
            'device_access' => $deviceAccess,
        ];
    }
}
