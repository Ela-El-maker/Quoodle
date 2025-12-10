#pragma once

#include <string>

struct TelemetrySample {
    std::string cpu;
    std::string ram;
    std::string disk;
    std::string network_tx;
    std::string network_rx;
};

class TelemetryCollector {
public:
    TelemetrySample collect();
};
