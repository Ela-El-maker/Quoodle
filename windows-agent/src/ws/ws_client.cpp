#include "ws_client.hpp"

#include <chrono>
#include <iostream>
#include <thread>

#include <ixwebsocket/IXNetSystem.h>
#include <ixwebsocket/IXWebSocket.h>

WsClient::WsClient(std::string endpoint) : endpoint_(std::move(endpoint)) {}

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
