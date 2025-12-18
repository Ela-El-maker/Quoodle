#include "telemetry_collector.hpp"
#include <cstdio>
#include <iostream>

#ifdef _WIN32

TelemetryCollector::TelemetryCollector() {
    if (PdhOpenQuery(NULL, NULL, &cpuQuery) == ERROR_SUCCESS) {
        // \Processor(_Total)\% Processor Time is the localized counter for total CPU
        if (PdhAddCounter(cpuQuery, L"\\Processor(_Total)\\% Processor Time", NULL, &cpuTotal) == ERROR_SUCCESS) {
            PdhCollectQueryData(cpuQuery);
            pdhInitialized = true;
        }
    }
}

TelemetryCollector::~TelemetryCollector() {
    if (pdhInitialized) {
        PdhCloseQuery(cpuQuery);
    }
}

std::string TelemetryCollector::get_cpu_usage() {
    if (!pdhInitialized) return "0.0%";
    
    PDH_FMT_COUNTERVALUE counterVal;
    PdhCollectQueryData(cpuQuery);
    PdhGetFormattedCounterValue(cpuTotal, PDH_FMT_DOUBLE, NULL, &counterVal);
    
    char buf[16];
    std::snprintf(buf, sizeof(buf), "%.1f%%", counterVal.doubleValue);
    return std::string(buf);
}

std::string TelemetryCollector::get_ram_usage() {
    MEMORYSTATUSEX memInfo;
    memInfo.dwLength = sizeof(MEMORYSTATUSEX);
    if (GlobalMemoryStatusEx(&memInfo)) {
        char buf[16];
        std::snprintf(buf, sizeof(buf), "%ld%%", memInfo.dwMemoryLoad);
        return std::string(buf);
    }
    return "0%";
}

std::string TelemetryCollector::get_disk_usage() {
    ULARGE_INTEGER freeBytesAvailable, totalNumberOfBytes, totalNumberOfFreeBytes;
    // Checks the root directory of the current drive
    if (GetDiskFreeSpaceExA("C:\\", &freeBytesAvailable, &totalNumberOfBytes, &totalNumberOfFreeBytes)) {
        double total = static_cast<double>(totalNumberOfBytes.QuadPart);
        double free = static_cast<double>(totalNumberOfFreeBytes.QuadPart);
        double used_pct = ((total - free) / total) * 100.0;
        
        char buf[16];
        std::snprintf(buf, sizeof(buf), "%.1f%%", used_pct);
        return std::string(buf);
    }
    return "0%";
}

std::pair<std::string, std::string> TelemetryCollector::get_network_throughput() {
    PMIB_IF_TABLE2 table = NULL;
    uint64_t current_rx = 0;
    uint64_t current_tx = 0;
    auto now = std::chrono::steady_clock::now();

    if (GetIfTable2(&table) == NO_ERROR) {
        for (ULONG i = 0; i < table->NumEntries; i++) {
            const MIB_IF_ROW2& row = table->Table[i];
            
            // Only count physical interfaces that are operational
            if (row.Type != IF_TYPE_SOFTWARE_LOOPBACK && row.OperStatus == IfOperStatusUp) {
                current_rx += row.InOctets;
                current_tx += row.OutOctets;
            }
        }
        FreeMibTable(table);
    }

    // Calculate Delta
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(now - lastNetStats.timestamp).count();
    if (duration <= 0) return {"0.0Mbps", "0.0Mbps"};

    // Calculate Megabits per second (Octets * 8 / 1024 / 1024 / (ms/1000))
    double rx_mbps = ((current_rx - lastNetStats.rx_bytes) * 8.0 / 1024.0 / 1024.0) / (duration / 1000.0);
    double tx_mbps = ((current_tx - lastNetStats.tx_bytes) * 8.0 / 1024.0 / 1024.0) / (duration / 1000.0);

    // Save for next sample
    lastNetStats = { current_rx, current_tx, now };

    char rx_buf[32], tx_buf[32];
    std::snprintf(rx_buf, sizeof(rx_buf), "%.2fMbps", rx_mbps < 0 ? 0 : rx_mbps);
    std::snprintf(tx_buf, sizeof(tx_buf), "%.2fMbps", tx_mbps < 0 ? 0 : tx_mbps);

    return { std::string(rx_buf), std::string(tx_buf) };
}

TelemetrySample TelemetryCollector::collect() {
    TelemetrySample s;
    s.cpu = get_cpu_usage();
    s.ram = get_ram_usage();
    s.disk = get_disk_usage();
    
    auto net = get_network_throughput();
    s.network_rx = net.first;
    s.network_tx = net.second;
    
    return s;
}

#endif
