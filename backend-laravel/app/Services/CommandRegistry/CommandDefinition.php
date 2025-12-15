<?php

namespace App\Services\CommandRegistry;

use Illuminate\Support\Facades\Validator;

class CommandDefinition
{
    public function __construct(
        public string $name,
        public string $riskLevel,
        public string $minRole,
        public bool $requires2fa,
        public bool $allowedInQuarantine,
        public array $paramsRules = []
    ) {
    }

    public function validate(array $params): array
    {
        $validator = Validator::make($params, $this->paramsRules);

        if ($validator->fails()) {
            return [
                'valid' => false,
                'errors' => $validator->errors()->all(),
            ];
        }

        return ['valid' => true, 'errors' => []];
    }

    public function isRoleAllowed(string $role): bool
    {
        $order = ['user' => 1, 'analyst' => 2, 'admin' => 3];
        $roleWeight = $order[strtolower($role)] ?? 0;
        $minWeight = $order[strtolower($this->minRole)] ?? PHP_INT_MAX;

        return $roleWeight >= $minWeight;
    }
}
