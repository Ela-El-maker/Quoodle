<?php

namespace App\Services\CommandRegistry;

class CommandDefinition
{
    public function __construct(public string $name, public array $paramsSchema = [])
    {
    }
}
