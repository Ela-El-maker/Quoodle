#pragma once

#include <string>
#include "../kernel/ioctl_client.hpp"
#include "../agent_state.hpp"

/**
 * CommandDispatcher
 * Maps incoming command method names to IoctlClient operations.
 * Requires AgentState for policy_hash and other contextual data.
 */
class CommandDispatcher
{
public:
    CommandDispatcher() = default;

    /**
     * Dispatch a command to the kernel service.
     * @param method The opcode/method name (e.g., "lock_screen", "EXEC_REBOOT")
     * @param request_id Unique request identifier
     * @param state Agent state for policy_hash and other context
     * @param params_json JSON parameters for the operation (optional)
     * @param command_message_id Originating command ID from controller (optional)
     */
    KernelExecResult dispatch(const std::string &method, const std::string &request_id,
                              const AgentState &state,
                              const std::string &params_json = "{}",
                              const std::string &command_message_id = "")
    {
        // System Control opcodes
        if (method == "lock_screen" || method == "EXEC_LOCK_SCREEN")
        {
            return ioctl_.lock_screen(request_id, state, command_message_id);
        }
        if (method == "reboot" || method == "reboot_device" || method == "EXEC_REBOOT")
        {
            return ioctl_.reboot(request_id, state, command_message_id);
        }
        if (method == "shutdown" || method == "shutdown_device" || method == "EXEC_SHUTDOWN")
        {
            return ioctl_.shutdown(request_id, state, command_message_id);
        }
        if (method == "logout" || method == "EXEC_LOGOUT")
        {
            return ioctl_.logout(request_id, state, command_message_id);
        }

        // Agent Internal opcodes
        if (method == "ping")
        {
            return ioctl_.ping(request_id, state, command_message_id);
        }
        if (method == "collect_system_info" || method == "COLLECT_SYSTEM_INFO")
        {
            return ioctl_.collect_system_info(request_id, state, command_message_id, params_json);
        }
        if (method == "screenshot" || method == "screenshot-capture" || method == "CAPTURE_SCREENSHOT" || method == "EXEC_CAPTURE_SCREENSHOT")
        {
            return ioctl_.capture_screenshot_authorize(request_id, state, command_message_id, params_json);
        }
        if (method == "get_process_list" || method == "GET_PROCESS_LIST")
        {
            return ioctl_.get_process_list(request_id, state, command_message_id);
        }
        if (method == "validate_update_package" || method == "VALIDATE_UPDATE_PACKAGE")
        {
            std::string package_path = extract_param(params_json, "package_path");
            return ioctl_.validate_update_package(request_id, state, package_path, command_message_id);
        }

        // Update & Staging opcodes
        if (method == "stage_update" || method == "STAGE_UPDATE")
        {
            std::string version = extract_param(params_json, "version");
            std::string package_path = extract_param(params_json, "package_path");
            return ioctl_.stage_update(request_id, state, version, package_path, command_message_id);
        }
        if (method == "commit_update" || method == "COMMIT_UPDATE")
        {
            return ioctl_.commit_update(request_id, state, command_message_id);
        }
        if (method == "rollback_update" || method == "ROLLBACK_UPDATE")
        {
            std::string reason = extract_param(params_json, "reason");
            return ioctl_.rollback_update(request_id, state, reason, command_message_id);
        }

        // Security & Integrity opcodes
        if (method == "run_attestation" || method == "RUN_ATTESTATION")
        {
            return ioctl_.run_attestation(request_id, state, command_message_id);
        }
        if (method == "run_tamper_check" || method == "RUN_TAMPER_CHECK")
        {
            return ioctl_.run_tamper_check(request_id, state, command_message_id);
        }
        if (method == "self_repair" || method == "SELF_REPAIR")
        {
            std::string component = extract_param(params_json, "component");
            return ioctl_.self_repair(request_id, state, component, command_message_id);
        }

        // Unknown opcode
        KernelExecResult r;
        r.request_id = request_id;
        r.status = "invalid_opcode";
        r.result = "";
        r.error_code = 4002;
        r.error_message = "INVALID_OPCODE: " + method;
        return r;
    }

private:
    IoctlClient ioctl_;

    // Simple JSON string extractor (for params)
    static std::string extract_param(const std::string &json, const std::string &key)
    {
        std::string needle = "\"" + key + "\":\"";
        auto pos = json.find(needle);
        if (pos == std::string::npos)
            return "";
        auto start = pos + needle.size();
        auto end = json.find('"', start);
        if (end == std::string::npos)
            return "";
        return json.substr(start, end - start);
    }
};
