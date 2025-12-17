#pragma once

#include <string>
#include <vector>
#include <unordered_map>

/**
 * Collects system metrics based on requested fields.
 * @param fields List of metrics to collect (e.g., "cpu", "ram", "disk", "uptime", "os").
 * If empty, all metrics are collected.
 * @return A map of metric names to their string values.
 */
std::unordered_map<std::string, std::string> execute_collect_system_info(
    const std::vector<std::string>& fields = {}
);
