#include "telemetry_collector.hpp"

TelemetrySample TelemetryCollector::collect() {
    TelemetrySample s;
    s.cpu = "10%";
    s.ram = "20%";
    s.disk = "30%";
    s.network_tx = "1Mbps";
    s.network_rx = "1Mbps";
    return s;
}
