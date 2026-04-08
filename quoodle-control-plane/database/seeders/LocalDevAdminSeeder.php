<?php

namespace Database\Seeders;

use App\Models\User;
use Illuminate\Database\Seeder;

class LocalDevAdminSeeder extends Seeder
{
    public function run(): void
    {
        $email = (string) env('DEV_ADMIN_EMAIL', 'admin@quoodle.com');
        $displayName = (string) env('DEV_ADMIN_NAME', 'Quoodle Admin');

        User::updateOrCreate(
            ['email' => $email],
            [
                'display_name' => $displayName,
                'role' => User::ROLE_ADMIN,
            ],
        );
    }
}
