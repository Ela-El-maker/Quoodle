<?php

namespace App\Services\Commands\Registry;

class CommandDefinition
{
    public function __construct(public readonly string $name, public readonly array $paramsSchema = [])
    {
    }
}
