<?php

namespace Database\Seeders;

use App\Models\PolicyProfile;
use Illuminate\Database\Seeder;

class AppLockPolicySeeder extends Seeder
{
    public function run(): void
    {
        PolicyProfile::query()->updateOrCreate(
            ['profile_id' => 'app_lock_v1'],
            [
                'description' => 'App lockdown V1 policy bundle',
                'rules' => [
                    'enabled' => false,
                    'mode' => 'blocklist',
                    'fail_mode' => 'open',
                    'policy_version' => (string) config('policy.version'),
                    'policy_hash' => (string) config('policy.master_hash'),
                    'event_dedupe_sec' => 30,
                    'updated_at' => now()->toIso8601String(),
                    'rules' => [],
                ],
            ]
        );
    }
}

