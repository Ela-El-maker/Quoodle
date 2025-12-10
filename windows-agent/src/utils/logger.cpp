#include <iostream>
#include <string>

void log_info(const std::string& msg) {
    std::cout << "[agent] " << msg << std::endl;
}

void log_error(const std::string& msg) {
    std::cerr << "[agent][error] " << msg << std::endl;
}
