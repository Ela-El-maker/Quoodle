#include "logger.hpp"

#include <iostream>

namespace utils {

void log_info(const std::string& msg) {
    std::cout << "[kernel] " << msg << std::endl;
}

void log_error(const std::string& msg) {
    std::cerr << "[kernel][error] " << msg << std::endl;
}

}  // namespace utils
