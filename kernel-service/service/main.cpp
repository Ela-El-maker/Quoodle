#include "dispatcher.hpp"
#include "utils/logger.hpp"

#include <iostream>
#include <string>
#include <sstream>

static std::string json_escape(const std::string &s)
{
    std::string out;
    for (char c : s)
    {
        switch (c)
        {
        case '\\':
            out += "\\\\";
            break;
        case '"':
            out += "\\\"";
            break;
        case '\n':
            out += "\\n";
            break;
        case '\r':
            out += "\\r";
            break;
        case '\t':
            out += "\\t";
            break;
        default:
            out += c;
            break;
        }
    }
    return out;
}

static std::string to_json(const KernelResponse &r)
{
    std::ostringstream oss;
    oss << "{";
    oss << "\"request_id\":\"" << json_escape(r.request_id) << "\",";
    oss << "\"status\":\"" << json_escape(r.status) << "\",";
    oss << "\"kernel_exec_id\":\"" << json_escape(r.kernel_exec_id) << "\",";
    oss << "\"timestamp\":\"" << json_escape(r.timestamp) << "\",";
    oss << "\"result\":\"" << json_escape(r.result) << "\",";
    oss << "\"error_code\":" << r.error_code << ",";
    oss << "\"error_message\":\"" << json_escape(r.error_message) << "\",";
    oss << "\"sig\":\"" << json_escape(r.sig) << "\"";
    oss << "}";
    return oss.str();
}

int main(int argc, char **argv)
{
    // CLI one-shot mode: kernel_service --once <opcode> <request_id>
    if (argc >= 2 && std::string(argv[1]) == "--once")
    {
        std::string opcode = (argc >= 3) ? argv[2] : std::string();
        std::string request_id = (argc >= 4) ? argv[3] : std::string("req-unknown");
        Dispatcher disp;
        KernelResponse resp;
        if (opcode == "lock_screen")
        {
            resp = disp.handle_lock_screen(request_id);
        }
        else if (opcode == "ping")
        {
            resp = disp.handle_ping(request_id);
        }
        else
        {
            resp = disp.handle_unknown(request_id, opcode);
        }
        std::cout << to_json(resp) << std::endl;
        return 0;
    }

    utils::log_info("KernelService placeholder started (interactive mode)");
    // Normally runs as a service / IOCTL dispatcher. For Phase 6 minimal stub, nothing else is required.
    return 0;
}
