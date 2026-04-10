#include "telemetry_collector.hpp"
#include <cstdio>
#include <iostream>
#include <cstdlib>

#ifdef _WIN32
#include <winreg.h>
#endif

#ifdef _WIN32

TelemetryCollector::TelemetryCollector()
{
    if (PdhOpenQueryW(NULL, 0, &cpuQuery) == ERROR_SUCCESS)
    {
        // \Processor(_Total)\% Processor Time is the localized counter for total CPU
        if (PdhAddCounterW(cpuQuery, L"\\Processor(_Total)\\% Processor Time", 0, &cpuTotal) == ERROR_SUCCESS)
        {
            PdhCollectQueryData(cpuQuery);
            pdhInitialized = true;
        }
    }
}

TelemetryCollector::~TelemetryCollector()
{
    if (pdhInitialized)
    {
        PdhCloseQuery(cpuQuery);
    }
}

std::string TelemetryCollector::get_cpu_usage()
{
    if (!pdhInitialized)
        return "0.0";

    PDH_FMT_COUNTERVALUE counterVal;
    PdhCollectQueryData(cpuQuery);
    PdhGetFormattedCounterValue(cpuTotal, PDH_FMT_DOUBLE, NULL, &counterVal);

    char buf[16];
    std::snprintf(buf, sizeof(buf), "%.1f", counterVal.doubleValue);
    return std::string(buf);
}

std::string TelemetryCollector::get_ram_usage()
{
    MEMORYSTATUSEX memInfo;
    memInfo.dwLength = sizeof(MEMORYSTATUSEX);
    if (GlobalMemoryStatusEx(&memInfo))
    {
        char buf[16];
        std::snprintf(buf, sizeof(buf), "%ld", memInfo.dwMemoryLoad);
        return std::string(buf);
    }
    return "0";
}

std::string TelemetryCollector::get_disk_usage()
{
    ULARGE_INTEGER freeBytesAvailable, totalNumberOfBytes, totalNumberOfFreeBytes;
    // Checks the root directory of the current drive
    if (GetDiskFreeSpaceExA("C:\\", &freeBytesAvailable, &totalNumberOfBytes, &totalNumberOfFreeBytes))
    {
        double total = static_cast<double>(totalNumberOfBytes.QuadPart);
        double free = static_cast<double>(totalNumberOfFreeBytes.QuadPart);
        double used_pct = ((total - free) / total) * 100.0;

        char buf[16];
        std::snprintf(buf, sizeof(buf), "%.1f", used_pct);
        return std::string(buf);
    }
    return "0";
}

std::pair<std::string, std::string> TelemetryCollector::get_network_throughput()
{
    PMIB_IF_TABLE2 table = NULL;
    uint64_t current_rx = 0;
    uint64_t current_tx = 0;
    auto now = std::chrono::steady_clock::now();

    if (GetIfTable2(&table) == NO_ERROR)
    {
        for (ULONG i = 0; i < table->NumEntries; i++)
        {
            const MIB_IF_ROW2 &row = table->Table[i];

            // Only count physical interfaces that are operational
            if (row.Type != IF_TYPE_SOFTWARE_LOOPBACK && row.OperStatus == IfOperStatusUp)
            {
                current_rx += row.InOctets;
                current_tx += row.OutOctets;
            }
        }
        FreeMibTable(table);
    }

    // Calculate Delta
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(now - lastNetStats.timestamp).count();
    if (duration <= 0)
        return {"0.0", "0.0"};

    // Calculate Megabits per second (Octets * 8 / 1024 / 1024 / (ms/1000))
    double rx_mbps = ((current_rx - lastNetStats.rx_bytes) * 8.0 / 1024.0 / 1024.0) / (duration / 1000.0);
    double tx_mbps = ((current_tx - lastNetStats.tx_bytes) * 8.0 / 1024.0 / 1024.0) / (duration / 1000.0);

    // Save for next sample
    lastNetStats = {current_rx, current_tx, now};

    char rx_buf[32], tx_buf[32];
    std::snprintf(rx_buf, sizeof(rx_buf), "%.2f", rx_mbps < 0 ? 0 : rx_mbps);
    std::snprintf(tx_buf, sizeof(tx_buf), "%.2f", tx_mbps < 0 ? 0 : tx_mbps);

    return {std::string(rx_buf), std::string(tx_buf)};
}

std::string TelemetryCollector::get_battery_pct()
{
    SYSTEM_POWER_STATUS power{};
    if (GetSystemPowerStatus(&power) && power.BatteryLifePercent != 255)
    {
        return std::to_string(static_cast<int>(power.BatteryLifePercent));
    }
    return "";
}

std::string TelemetryCollector::get_os_build()
{
    if (const char *env_build = std::getenv("AGENT_OS_BUILD"))
    {
        if (*env_build)
        {
            return env_build;
        }
    }

    HKEY hKey = nullptr;
    constexpr const char *kPath = "SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion";
    if (RegOpenKeyExA(HKEY_LOCAL_MACHINE, kPath, 0, KEY_READ | KEY_WOW64_64KEY, &hKey) != ERROR_SUCCESS)
    {
        return "";
    }

    char value[64] = {0};
    DWORD size = sizeof(value);
    LONG rc = RegQueryValueExA(hKey, "CurrentBuildNumber", nullptr, nullptr, reinterpret_cast<LPBYTE>(value), &size);
    if (rc != ERROR_SUCCESS)
    {
        size = sizeof(value);
        rc = RegQueryValueExA(hKey, "CurrentBuild", nullptr, nullptr, reinterpret_cast<LPBYTE>(value), &size);
    }

    if (rc != ERROR_SUCCESS)
    {
        RegCloseKey(hKey);
        return "";
    }

    const std::string build = std::string(value);
    if (build.empty())
    {
        RegCloseKey(hKey);
        return "";
    }

    DWORD ubr = 0;
    DWORD ubrSize = sizeof(ubr);
    DWORD ubrType = REG_DWORD;
    rc = RegQueryValueExA(
        hKey,
        "UBR",
        nullptr,
        &ubrType,
        reinterpret_cast<LPBYTE>(&ubr),
        &ubrSize
    );
    RegCloseKey(hKey);

    if (rc == ERROR_SUCCESS && ubrType == REG_DWORD)
    {
        return build + "." + std::to_string(ubr);
    }

    return build;
}

TelemetrySample TelemetryCollector::collect()
{
    TelemetrySample s;
    s.cpu = get_cpu_usage();
    s.ram = get_ram_usage();
    s.disk = get_disk_usage();

    auto net = get_network_throughput();
    s.network_rx = net.first;
    s.network_tx = net.second;
    s.battery_pct = get_battery_pct();
    s.os_build = get_os_build();
    if (const char *agent_version = std::getenv("AGENT_VERSION"))
    {
        s.agent_version = agent_version;
    }
    else
    {
        s.agent_version = "0.0.1";
    }
    if (const char *risk_score = std::getenv("AGENT_RISK_SCORE_HINT"))
    {
        s.risk_score = risk_score;
    }

    return s;
}

#endif
