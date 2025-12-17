#ifdef _WIN32

#include <windows.h>
#include <thread>
#include <string>
#include <chrono>
#include <iostream>

#include "../../src/kernel/ioctl_client.hpp"

static std::string to_json_response(const std::string &request_id, const std::string &status, const std::string &result)
{
    return std::string("{\"request_id\":\"") + request_id + "\",\"status\":\"" + status + "\",\"kernel_exec_id\":\"kexec-test\",\"timestamp\":\"2025-12-17T00:00:00Z\",\"result\":\"" + result + "\",\"error_code\":0,\"error_message\":\"\",\"sig\":\"test-sig\"}";
}

// Simple mock pipe server that accepts one request then returns a response.
static void run_mock_pipe_server()
{
    const char *pipeName = "\\\\.\\pipe\\KernelService";
    HANDLE hPipe = CreateNamedPipeA(
        pipeName,
        PIPE_ACCESS_DUPLEX,
        PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT,
        1,
        8192,
        8192,
        0,
        NULL);

    if (hPipe == INVALID_HANDLE_VALUE)
    {
        std::cerr << "mock_pipe: CreateNamedPipeA failed\n";
        return;
    }

    BOOL connected = ConnectNamedPipe(hPipe, NULL) ? TRUE : (GetLastError() == ERROR_PIPE_CONNECTED);
    if (!connected)
    {
        CloseHandle(hPipe);
        std::cerr << "mock_pipe: ConnectNamedPipe failed\n";
        return;
    }

    // Read request
    std::string req;
    {
        char buf[4096];
        DWORD read = 0;
        while (true)
        {
            BOOL ok = ReadFile(hPipe, buf, sizeof(buf), &read, NULL);
            if (!ok || read == 0)
                break;
            req.append(buf, buf + read);
            if (read < (DWORD)sizeof(buf))
                break;
        }
    }

    // Look for request_id and opcode in simple way
    auto find_val = [&](const std::string &key) -> std::string
    {
        std::string needle = '"' + key + '"';
        auto pos = req.find(needle);
        if (pos == std::string::npos)
            return std::string();
        auto colon = req.find(':', pos + needle.size());
        if (colon == std::string::npos)
            return std::string();
        auto q1 = req.find('"', colon);
        if (q1 == std::string::npos)
            return std::string();
        auto q2 = req.find('"', q1 + 1);
        if (q2 == std::string::npos)
            return std::string();
        return req.substr(q1 + 1, q2 - q1 - 1);
    };

    std::string opcode = find_val("opcode");
    std::string request_id = find_val("request_id");
    if (request_id.empty())
        request_id = "test-req";

    std::string response = to_json_response(request_id, "ok", opcode == "ping" ? "pong" : "lock_screen_executed");

    DWORD written = 0;
    WriteFile(hPipe, response.c_str(), (DWORD)response.size(), &written, NULL);
    FlushFileBuffers(hPipe);
    DisconnectNamedPipe(hPipe);
    CloseHandle(hPipe);
}

int main()
{
    // Start mock server
    std::thread server_thread(run_mock_pipe_server);

    // Give server a short moment to create pipe and wait
    std::this_thread::sleep_for(std::chrono::milliseconds(100));

    IoctlClient client;
    auto res = client.ping("req-1");
    if (res.status != "ok" || res.result != "pong")
    {
        std::cerr << "ping failed: status=" << res.status << " result=" << res.result << "\n";
        return 2;
    }

    // Start another server instance for lock_screen (single-use mock)
    std::thread server_thread2(run_mock_pipe_server);
    std::this_thread::sleep_for(std::chrono::milliseconds(100));

    auto res2 = client.lock_screen("req-2");
    if (res2.status != "ok")
    {
        std::cerr << "lock_screen failed: status=" << res2.status << "\n";
        return 3;
    }

    server_thread.join();
    server_thread2.join();

    std::cout << "ioctl_integration_test: PASS\n";
    return 0;
}

#else

#include <iostream>
int main()
{
    std::cout << "ioctl_integration_test: SKIPPED (non-Windows)\n";
    return 0;
}

#endif
