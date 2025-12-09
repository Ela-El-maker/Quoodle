#include "logger.hpp"

#include <iostream>

namespace utils {

void log_info(const std::string& msg) {
    std::cout << "[kernel] " << msg << std::endl;
}

}  // namespace utils
