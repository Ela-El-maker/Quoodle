#include "command_processor.h"

#include <sys/utsname.h>
#include <unistd.h>
#include <fstream>
#include <sstream>
#include <vector>
#include <map>
#include <ifaddrs.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <net/if.h>
#include <netdb.h>

#include <cstdlib>
#include <cstring>

namespace {

bool EnvFlagEnabled(const char *name) {
    const char *value = std::getenv(name);
    if (!value || !*value) {
        return false;
    }
    return std::strcmp(value, "1") == 0 ||
           std::strcmp(value, "true") == 0 ||
           std::strcmp(value, "yes") == 0;
}

}  // namespace

namespace quoodle {

namespace {

nlohmann::json GetSysInfo() {
    nlohmann::json info;
    
    // Hostname
    char hostname[256] = {0};
    if (gethostname(hostname, sizeof(hostname)) == 0) {
        info["hostname"] = hostname;
    } else {
        info["hostname"] = "unknown";
    }

    // OS / Kernel
    struct utsname uts{};
    if (uname(&uts) == 0) {
        info["kernel_sysname"] = uts.sysname;
        info["kernel_release"] = uts.release;
        info["kernel_version"] = uts.version;
        info["machine"] = uts.machine;
        info["nodename"] = uts.nodename; // usually same as hostname
    }

    // Uptime
    std::ifstream upfile("/proc/uptime");
    if (upfile.good()) {
        double uptime_sec = 0.0;
        upfile >> uptime_sec;
        info["uptime_seconds"] = uptime_sec;
    }

    // Load Average
    double load[3] = {0};
    if (getloadavg(load, 3) >= 0) {
        info["load_avg"] = {load[0], load[1], load[2]};
    }

    // Logged in user (simple env check for agent context, mostly for debug)
    const char* user = std::getenv("USER");
    if (user) info["agent_user"] = user;

    return info;
}

nlohmann::json GetNetInfo() {
    nlohmann::json info;
    nlohmann::json ifaces = nlohmann::json::object();

    struct ifaddrs *ifaddr, *ifa;
    if (getifaddrs(&ifaddr) != -1) {
        for (ifa = ifaddr; ifa != nullptr; ifa = ifa->ifa_next) {
            if (ifa->ifa_addr == nullptr) continue;
            std::string name = ifa->ifa_name;
            int family = ifa->ifa_addr->sa_family;

            if (!ifaces.contains(name)) {
                ifaces[name] = nlohmann::json::array();
            }

            char host[NI_MAXHOST];
            if (getnameinfo(ifa->ifa_addr,
                            (family == AF_INET) ? sizeof(struct sockaddr_in) : sizeof(struct sockaddr_in6),
                            host, NI_MAXHOST, nullptr, 0, NI_NUMERICHOST) == 0) {
                
                nlohmann::json addr_obj;
                addr_obj["address"] = host;
                if (family == AF_INET) addr_obj["family"] = "ipv4";
                else if (family == AF_INET6) addr_obj["family"] = "ipv6";
                else addr_obj["family"] = "unknown";
                ifaces[name].push_back(addr_obj);
            }
        }
        freeifaddrs(ifaddr);
    }
    info["interfaces"] = ifaces;

    // Routes
    nlohmann::json routes = nlohmann::json::array();
    std::ifstream rfile("/proc/net/route");
    if (rfile.good()) {
        std::string line;
        std::getline(rfile, line); // header
        while (std::getline(rfile, line)) { // iface dest gw flags ...
            std::istringstream iss(line);
            std::string iface, dest_hex, gw_hex;
            if (iss >> iface >> dest_hex >> gw_hex) {
               unsigned int dest_val = 0;
               unsigned int gw_val = 0;
               std::stringstream ss; 
               ss << std::hex << dest_hex; ss >> dest_val;
               ss.clear(); ss.str("");
               ss << std::hex << gw_hex; ss >> gw_val;
               
               struct in_addr dest_addr, gw_addr;
               dest_addr.s_addr = dest_val;
               gw_addr.s_addr = gw_val;

               nlohmann::json route;
               route["iface"] = iface;
               route["destination"] = inet_ntoa(dest_addr);
               route["gateway"] = inet_ntoa(gw_addr);
               routes.push_back(route);
            }
        }
    }
    info["routes"] = routes;

    return info;
}

}  // namespace

CommandProcessor::CommandProcessor(Outbox &outbox, PrivilegedClient &privileged, AgentStateStore &state)
    : outbox_(outbox), privileged_(privileged), state_(state) {}

ExecutionResult CommandProcessor::Handle(const CommandEnvelope &command) {
    if (!command.delivery_id.empty()) {
        state_.SetLastDeliveryId(command.delivery_id);
    }
    bool out_of_order = EnvFlagEnabled("QUOODLE_FAULT_OUT_OF_ORDER_RESULT");
    if (command.requires_ack && !out_of_order) {
        outbox_.EnqueueAck(command.command_id, command.device_id, "received", "");
    }

    CommandRequest request;
    request.command_id = command.command_id;
    request.method = command.method;
    request.params = command.params;
    request.policy_hash = command.policy_hash;

    ExecutionResult result;
    if (command.method == "sysinfo") {
        result.execution_state = "completed";
        result.status = "ok";
        result.result = GetSysInfo();
    } else if (command.method == "netinfo") {
        result.execution_state = "completed";
        result.status = "ok";
        result.result = GetNetInfo();
    } else {
        result = privileged_.Execute(request);
    }

    outbox_.EnqueueResult(command.command_id, command.device_id, result);
    if (command.requires_ack && out_of_order) {
        outbox_.EnqueueAck(command.command_id, command.device_id, "received", "");
    }
    ProcessedCommand processed;
    processed.command_id = command.command_id;
    processed.requires_ack = command.requires_ack;
    if (command.requires_ack) {
        processed.ack_status = "received";
        processed.ack_reason = "";
    }
    processed.result = result;
    state_.RememberCommand(processed);
    return result;
}

}  // namespace quoodle
