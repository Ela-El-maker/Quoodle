#ifdef _WIN32

#include <windows.h>
#include <thread>
#include <string>
#include <chrono>
#include <iostream>
#include <atomic>

#include "../../src/kernel/ioctl_client.hpp"

// Atomic flag to ensure threads don't overlap on the pipe handle
static std::atomic<bool> server_ready(false);

static std::string to_json_response(const std::string &request_id, const std::string &status, const std::string &result)
{
    // Simplified JSON generator for testing
    return std::string("{\"request_id\":\"") + request_id + 
           "\",\"status\":\"" + status + 
           "\",\"kernel_exec_id\":\"kexec-test\",\"timestamp\":\"2025-12-18T00:00:00Z\",\"result\":\"" + 
           result + "\",\"error_code\":0,\"error_message\":\"\",\"sig\":\"test-sig\"}";
}

// Simple mock pipe server that handles exactly ONE connection
static void run_mock_pipe_server()
{
    const char *pipeName = "\\\\.\\pipe\\KernelService";
    
    // Create the pipe with a security descriptor that allows local access
    HANDLE hPipe = CreateNamedPipeA(
        pipeName,
        PIPE_ACCESS_DUPLEX,
        PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT,
        PIPE_UNLIMITED_INSTANCES, // More robust than '1'
        8192,
        8192,
        0,
        NULL);

    if (hPipe == INVALID_HANDLE_VALUE)
    {
        std::cerr << "mock_pipe: CreateNamedPipeA failed (err=" << GetLastError() << ")\n";
        return;
    }

    // Signal main thread that pipe is open
    server_ready = true;

    BOOL connected = ConnectNamedPipe(hPipe, NULL) ? TRUE : (GetLastError() == ERROR_PIPE_CONNECTED);
    if (!connected)
    {
        std::cerr << "mock_pipe: ConnectNamedPipe failed (err=" << GetLastError() << ")\n";
        CloseHandle(hPipe);
        return;
    }

    // Read request from client
    std::string req;
    char buf[4096];
    DWORD bytesRead = 0;
    if (ReadFile(hPipe, buf, sizeof(buf) - 1, &bytesRead, NULL) && bytesRead > 0)
    {
        buf[bytesRead] = '\0';
        req = buf;
    }

    // Simple lambda to extract values from the raw JSON string
    auto find_val = [&](const std::string &key) -> std::string
    {
        std::string needle = "\"" + key + "\"";
        auto pos = req.find(needle);
        if (pos == std::string::npos) return "";
        auto q1 = req.find("\"", req.find(":", pos) + 1);
        auto q2 = req.find("\"", q1 + 1);
        return req.substr(q1 + 1, q2 - q1 - 1);
    };

    std::string opcode = find_val("opcode");
    std::string request_id = find_val("request_id");
    if (request_id.empty()) request_id = "test-req";

    // Prepare response based on the opcode sent
    std::string result_str = (opcode == "ping") ? "pong" : "lock_screen_executed";
    std::string response = to_json_response(request_id, "ok", result_str);

    DWORD written = 0;
    WriteFile(hPipe, response.c_str(), (DWORD)response.size(), &written, NULL);
    FlushFileBuffers(hPipe);
    
    DisconnectNamedPipe(hPipe);
    CloseHandle(hPipe);
}

int main()
{
    IoctlClient client;

    // --- TEST 1: PING ---
    {
        server_ready = false;
        std::thread t(run_mock_pipe_server);
        while(!server_ready) std::this_thread::yield(); // Wait for server to init

        auto res = client.ping("req-ping-1");
        if (res.status != "ok" || res.result != "pong")
        {
            std::cerr << "TEST FAILED: ping. Status=" << res.status << ", Result=" << res.result << "\n";
            t.join();
            return 2;
        }
        t.join();
        std::cout << "Sub-test: Ping... OK\n";
    }

    // --- TEST 2: LOCK_SCREEN ---
    {
        server_ready = false;
        std::thread t(run_mock_pipe_server);
        while(!server_ready) std::this_thread::yield();

        auto res = client.lock_screen("req-lock-2");
        if (res.status != "ok" || res.result != "lock_screen_executed")
        {
            std::cerr << "TEST FAILED: lock_screen. Status=" << res.status << "\n";
            t.join();
            return 3;
        }
        t.join();
        std::cout << "Sub-test: LockScreen... OK\n";
    }

    std::cout << "ioctl_integration_test: ALL PASS\n";
    return 0;
}

#else
#include <iostream>
int main() {
    std::cout << "ioctl_integration_test: SKIPPED (non-Windows)\n";
    return 0;
}
#endif
