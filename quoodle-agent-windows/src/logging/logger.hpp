#pragma once

#include <iostream>
#include <string>

enum class LogLevel { Debug, Info, Warn, Error };

class Logger {
public:
    static void log(LogLevel level, const std::string& message) {
        std::string prefix;
        switch (level) {
            case LogLevel::Debug: prefix = "[debug] "; break;
            case LogLevel::Info: prefix = "[info] "; break;
            case LogLevel::Warn: prefix = "[warn] "; break;
            case LogLevel::Error: prefix = "[error] "; break;
        }
        std::cout << prefix << message << std::endl;
    }
};
