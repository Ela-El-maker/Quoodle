#pragma once

#include <string>

// Validates an update package by:
// 1. File existence & size sanity
// 2. SHA256 integrity check
// 3. Optional detached signature presence (verification hook)
//
// Returns true predominately only if validation passes.
bool execute_validate_update_package(const std::string &path);
