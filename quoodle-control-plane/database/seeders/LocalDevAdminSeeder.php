<?php

namespace Database\Seeders;

use App\Models\User;
use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\Hash;

class LocalDevAdminSeeder extends Seeder
{
    public function run(): void
    {
        $email = (string) env('DEV_ADMIN_EMAIL', 'admin@quoodle.com');
        $password = (string) env('DEV_ADMIN_PASSWORD', 'password');
        $displayName = (string) env('DEV_ADMIN_NAME', 'Quoodle Admin');

        User::updateOrCreate(
            ['email' => $email],
            [
                'display_name' => $displayName,
                'password' => Hash::make($password),
                'public_key' => 'dev-public-key',
                'role' => User::ROLE_ADMIN,
            ],
        );
    }
}
