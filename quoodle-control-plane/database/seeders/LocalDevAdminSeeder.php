<?php

namespace Database\Seeders;

use App\Models\User;
use Illuminate\Database\Seeder;

class LocalDevAdminSeeder extends Seeder
{
    public function run(): void
    {
        $email = (string) env('DEV_ADMIN_EMAIL', 'feloela444@gmail.com');
        $displayName = (string) env('DEV_ADMIN_NAME', 'Feloela Admin');

        User::updateOrCreate(
            ['email' => $email],
            [
                'display_name' => $displayName,
                'role' => User::ROLE_ADMIN,
            ],
        );
    }
}
