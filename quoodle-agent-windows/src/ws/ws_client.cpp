#include "ws_client.hpp"

#include <chrono>
#include <iostream>
#include <thread>
#include <unordered_map>

#include <ixwebsocket/IXNetSystem.h>
#include <ixwebsocket/IXWebSocket.h>
#include <nlohmann/json.hpp>

#include "../kernel/ioctl_client.hpp"
#include "ws_protocol.hpp"

WsClient::WsClient(std::string endpoint, std::string device_id)
    : endpoint_(std::move(endpoint)), device_id_(std::move(device_id)), state_(device_id_) {}

void WsClient::set_initial_message(const std::string& message) {
    initial_message_ = message;
}

void WsClient::connect_and_run() {
    ix::initNetSystem();
    ix::WebSocket socket;
    socket.setUrl(endpoint_);

    socket.setOnMessageCallback([&](const ix::WebSocketMessagePtr& msg) {
        if (msg->type == ix::WebSocketMessageType::Open) {
            Logger::log(LogLevel::Info, "connected, sending AUTH");
            socket.sendText(initial_message_);
        } else if (msg->type == ix::WebSocketMessageType::Message) {
            Logger::log(LogLevel::Debug, std::string("received: ") + msg->str);
            try {
                auto parsed = nlohmann::json::parse(msg->str);
                std::string mtype = parsed.value("type", "");
                if (mtype == "AUTH_ACK") {
                    std::string session_id = parsed["body"].value("session_id", "");
                    if (!session_id.empty()) {
                        last_session_id_ = session_id;
                        state_.set_session_id(session_id);
                        if (!heartbeat_sent_) {
                            auto hb = build_signed_heartbeat_json(device_id_, session_id, "alive", 120, "ok");
                            socket.sendText(hb);
                            heartbeat_sent_ = true;
                        }
                        if (!telemetry_sent_) {
                            auto tel = build_signed_telemetry_json(device_id_, session_id);
                            socket.sendText(tel);
                            telemetry_sent_ = true;
                        }
                    }
                } else if (mtype == "POLICY_UPDATE") {
                    auto body = parsed["body"];
                    std::string policy_hash = body.value("policy_hash", "");
                    state_.set_policy_hash(policy_hash);
                    Logger::log(LogLevel::Info, "policy updated: " + policy_hash);
                } else if (mtype == "COMMAND_DELIVERY") {
                    std::string session_id = parsed.value("session_id", "");
                    auto body = parsed["body"];
                    auto envelope = body["command_envelope"];
                    std::string command_message_id = envelope.value("message_id", "");
                    std::string trace_id = envelope.value("trace_id", "");
                    std::string method = envelope["body"].value("method", "");
                    std::string policy_hash = envelope["meta"].value("policy_hash", "");

                    if (!session_id.empty() && !command_message_id.empty()) {
                        auto ack = build_command_ack_json(device_id_, session_id, command_message_id, "received", "");
                        socket.sendText(ack);

                        if (quarantine_.is_quarantined() && !quarantine_.is_allowed(method)) {
                            auto denied = build_command_result_json(device_id_, session_id, command_message_id,
                                                                    trace_id, "failed", "denied",
                                                                    "quarantined", "", "", 4001,
                                                                    quarantine_.reason());
                            socket.sendText(denied);
                            return;
                        }

                        if (!policy_hash.empty() && !state_.policy_hash().empty() && policy_hash != state_.policy_hash()) {
                            auto denied = build_command_result_json(device_id_, session_id, command_message_id,
                                                                    trace_id, "failed", "policy_mismatch",
                                                                    "policy hash mismatch", "", "", 4002, "");
                            socket.sendText(denied);
                            return;
                        }

                        IoctlClient ioctl;
                        if (method == "lock_screen") {
                            auto res = ioctl.lock_screen(command_message_id);
                            auto result_msg = build_command_result_json(device_id_, session_id, command_message_id,
                                                                        trace_id, "completed", "ok", "lock_screen done",
                                                                        "", "", res.error_code, res.error_message);
                            socket.sendText(result_msg);
                        } else if (method == "ping") {
                            auto res = ioctl.ping(command_message_id);
                            auto result_msg = build_command_result_json(device_id_, session_id, command_message_id,
                                                                        trace_id, "completed", "ok", res.result,
                                                                        "", "", res.error_code, res.error_message);
                            socket.sendText(result_msg);
                        } else {
                            auto not_supported = build_command_result_json(device_id_, session_id, command_message_id,
                                                                           trace_id, "failed", "unsupported",
                                                                           "command not supported", "", "", 4004, "");
                            socket.sendText(not_supported);
                        }
                    }
                } else if (mtype == "UPDATE_ANNOUNCE") {
                    std::string session_id = parsed.value("session_id", "");
                    auto body = parsed["body"];
                    std::string release_id = body.value("release_id", "");
                    std::string version = body.value("version", "");
                    if (!session_id.empty() && !release_id.empty()) {
                        std::unordered_map<std::string, std::string> manifest;
                        manifest["release_id"] = release_id;
                        manifest["version"] = version;
                        ota_.set_manifest(manifest);
                        state_.set_release(release_id);
                        auto status_msg = build_update_status_json(
                            device_id_, session_id, release_id, "precheck", version, 0, "acknowledged", 0, "", "");
                        socket.sendText(status_msg);
                    }
                }
            } catch (const std::exception& e) {
                Logger::log(LogLevel::Error, std::string("parse error: ") + e.what());
            }
        } else if (msg->type == ix::WebSocketMessageType::Error) {
            Logger::log(LogLevel::Error, std::string("ws error: ") + msg->errorInfo.reason);
        } else if (msg->type == ix::WebSocketMessageType::Close) {
            Logger::log(LogLevel::Info, "ws closed");
        }
    });

    socket.start();

    std::this_thread::sleep_for(std::chrono::seconds(5));

    socket.stop();
}
