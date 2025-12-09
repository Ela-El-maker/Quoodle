#include "ws_client.hpp"

#include <chrono>
#include <iostream>
#include <thread>

#include <ixwebsocket/IXNetSystem.h>
#include <ixwebsocket/IXWebSocket.h>
#include <nlohmann/json.hpp>

#include "../kernel/ioctl_client.hpp"
#include "ws_protocol.hpp"

WsClient::WsClient(std::string endpoint, std::string device_id)
    : endpoint_(std::move(endpoint)), device_id_(std::move(device_id)) {}

void WsClient::set_initial_message(const std::string& message) {
    initial_message_ = message;
}

void WsClient::connect_and_run() {
    ix::initNetSystem();
    ix::WebSocket socket;
    socket.setUrl(endpoint_);

    socket.setOnMessageCallback([&](const ix::WebSocketMessagePtr& msg) {
        if (msg->type == ix::WebSocketMessageType::Open) {
            std::cout << "[ws] connected, sending AUTH" << std::endl;
            socket.sendText(initial_message_);
        } else if (msg->type == ix::WebSocketMessageType::Message) {
            std::cout << "[ws] received: " << msg->str << std::endl;
            try {
                auto parsed = nlohmann::json::parse(msg->str);
                    std::string mtype = parsed.value("type", "");
                    if (mtype == "AUTH_ACK") {
                        std::string session_id = parsed["body"].value("session_id", "");
                        if (!session_id.empty()) {
                            last_session_id_ = session_id;
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
                } else if (mtype == "COMMAND_DELIVERY") {
                    std::string session_id = parsed.value("session_id", "");
                    auto body = parsed["body"];
                    auto envelope = body["command_envelope"];
                    std::string command_message_id = envelope.value("message_id", "");
                    std::string method = envelope["body"].value("method", "");

                    if (!session_id.empty() && !command_message_id.empty()) {
                        // Immediately ACK receipt
                        auto ack = build_command_ack_json(device_id_, session_id, command_message_id, "received", "");
                        socket.sendText(ack);

                        // Execute minimal opcodes (lock_screen, ping)
                        IoctlClient ioctl;
                        if (method == "lock_screen") {
                            auto res = ioctl.lock_screen(command_message_id);
                            if (!session_id.empty()) {
                                auto result_msg = build_command_result_json(device_id_, session_id, command_message_id,
                                                                            "completed", "ok", "lock_screen done",
                                                                            "", "", 0, "");
                                socket.sendText(result_msg);
                            }
                        } else if (method == "ping") {
                            auto res = ioctl.ping(command_message_id);
                            if (!session_id.empty()) {
                                auto result_msg = build_command_result_json(device_id_, session_id, command_message_id,
                                                                            "completed", "ok", res.result,
                                                                            "", "", 0, "");
                                socket.sendText(result_msg);
                            }
                        }
                    }
                } else if (mtype == "UPDATE_ANNOUNCE") {
                    std::string session_id = parsed.value("session_id", "");
                    auto body = parsed["body"];
                    std::string release_id = body.value("release_id", "");
                    std::string version = body.value("version", "");
                    if (!session_id.empty() && !release_id.empty()) {
                        auto status_msg = build_update_status_json(device_id_, session_id, release_id, "acknowledged", version);
                        socket.sendText(status_msg);
                    }
                }
            } catch (const std::exception& e) {
                std::cerr << "[ws] parse error: " << e.what() << std::endl;
            }
        } else if (msg->type == ix::WebSocketMessageType::Error) {
            std::cerr << "[ws] error: " << msg->errorInfo.reason << std::endl;
        } else if (msg->type == ix::WebSocketMessageType::Close) {
            std::cout << "[ws] closed" << std::endl;
        }
    });

    socket.start();

    std::this_thread::sleep_for(std::chrono::seconds(5));

    socket.stop();
}
