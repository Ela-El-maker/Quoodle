#include "dispatcher.hpp"
#include "utils/logger.hpp"

int main() {
    utils::log_info("KernelService placeholder started");
    // Normally runs as a service / IOCTL dispatcher. For Phase 6 minimal stub, nothing else is required.
    return 0;
}
