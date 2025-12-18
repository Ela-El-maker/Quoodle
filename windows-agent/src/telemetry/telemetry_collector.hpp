#pragma once
#include <string>
#include <map>

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <pdh.h>
#include <netioapi.h>
#include <chrono>

#pragma comment(lib, "pdh.lib")
#pragma comment(lib, "iphlpapi.lib")
#endif

struct TelemetrySample
{
    std::string cpu;
    std::string ram;
    std::string disk;
    std::string network_tx;
    std::string network_rx;
};

class TelemetryCollector
{
public:
    TelemetryCollector();
    ~TelemetryCollector();
    TelemetrySample collect();

private:
#ifdef _WIN32
    // CPU Logic
    PDH_HQUERY cpuQuery;
    PDH_HCOUNTER cpuTotal;
    bool pdhInitialized = false;

    // Network Logic
    struct NetStats
    {
        uint64_t rx_bytes;
        uint64_t tx_bytes;
        std::chrono::steady_clock::time_point timestamp;
    };
    NetStats lastNetStats{0, 0, std::chrono::steady_clock::now()};

    std::string get_cpu_usage();
    std::string get_ram_usage();
    std::string get_disk_usage();
    std::pair<std::string, std::string> get_network_throughput();
#endif
};
