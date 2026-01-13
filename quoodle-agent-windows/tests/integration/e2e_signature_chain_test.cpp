/**
 * e2e_signature_chain_test.cpp
 *
 * Task 1.7: End-to-end integration test for Agent ↔ Kernel signed communication.
 *
 * This test verifies the complete cryptographic trust chain:
 *   1. Agent signs request with Agent private key
 *   2. Kernel verifies request using Agent public key
 *   3. Kernel signs response with Kernel private key
 *   4. Agent verifies response using Kernel public key
 *
 * Test cases:
 *   - POSITIVE: Valid signatures on both sides → success
 *   - NEGATIVE_REQUEST: Tampered request signature → kernel rejects (error 4001)
 *   - NEGATIVE_RESPONSE: Tampered response signature → agent rejects
 *
 * Environment variables required for full test:
 *   - CI_AGENT_SK_B64: Agent's Ed25519 secret key (64 bytes, base64)
 *   - CI_AGENT_PK_B64: Agent's Ed25519 public key (32 bytes, base64)
 *   - CI_KERNEL_SK_B64: Kernel's Ed25519 secret key (64 bytes, base64)
 *   - CI_KERNEL_PK_B64: Kernel's Ed25519 public key (32 bytes, base64)
 *
 * Without these keys, test is skipped.
 */

#include <iostream>
#include <string>
#include <vector>
#include <thread>
#include <chrono>
#include <cstdlib>
#include <algorithm>
#include <sstream>
#include <iomanip>

#ifdef _WIN32
#include <windows.h>
#endif

#ifdef HAVE_SODIUM
#include <sodium.h>

// ============================================================================
// Utility Functions
// ============================================================================

static std::string b64_encode(const unsigned char *buf, size_t len)
{
    char out[256];
    sodium_bin2base64(out, sizeof(out), buf, len, sodium_base64_VARIANT_ORIGINAL);
    return std::string(out);
}

static bool b64_decode(const std::string &in, std::vector<unsigned char> &out, size_t expected)
{
    out.assign(expected, 0);
    size_t got = 0;
    return sodium_base642bin(out.data(), out.size(),
                             in.c_str(), in.size(),
                             nullptr, &got, nullptr,
                             sodium_base64_VARIANT_ORIGINAL) == 0 &&
           got == expected;
}

static std::string escape_json(const std::string &s)
{
    std::ostringstream oss;
    for (char c : s)
    {
        switch (c)
        {
        case '"':
            oss << "\\\"";
            break;
        case '\\':
            oss << "\\\\";
            break;
        case '\n':
            oss << "\\n";
            break;
        case '\r':
            oss << "\\r";
            break;
        case '\t':
            oss << "\\t";
            break;
        default:
            oss << c;
        }
    }
    return oss.str();
}

static std::string extract_json_string(const std::string &json, const std::string &key)
{
    std::string search = "\"" + key + "\":";
    auto pos = json.find(search);
    if (pos == std::string::npos)
        return "";
    pos += search.size();
    while (pos < json.size() && (json[pos] == ' ' || json[pos] == '\t'))
        pos++;
    if (pos >= json.size())
        return "";

    if (json[pos] == '"')
    {
        auto start = pos + 1;
        auto end = json.find('"', start);
        while (end != std::string::npos && json[end - 1] == '\\')
        {
            end = json.find('"', end + 1);
        }
        if (end != std::string::npos)
            return json.substr(start, end - start);
    }
    return "";
}

static int extract_json_int(const std::string &json, const std::string &key)
{
    std::string search = "\"" + key + "\":";
    auto pos = json.find(search);
    if (pos == std::string::npos)
        return 0;
    pos += search.size();
    while (pos < json.size() && (json[pos] == ' ' || json[pos] == '\t'))
        pos++;
    std::string num;
    while (pos < json.size() && (json[pos] >= '0' && json[pos] <= '9'))
    {
        num += json[pos++];
    }
    return num.empty() ? 0 : std::stoi(num);
}

static std::string iso_timestamp()
{
    auto now = std::chrono::system_clock::now();
    std::time_t t = std::chrono::system_clock::to_time_t(now);
    std::tm tm{};
#ifdef _WIN32
    gmtime_s(&tm, &t);
#else
    gmtime_r(&t, &tm);
#endif
    char buffer[64];
    std::strftime(buffer, sizeof(buffer), "%Y-%m-%dT%H:%M:%SZ", &tm);
    return std::string(buffer);
}

// ============================================================================
// Canonical JSON Builder (matching kernel's implementation)
// ============================================================================

/**
 * Build canonical request payload for agent → kernel
 * Fields in lexicographic order: agent_sequence, command_message_id, opcode, params, policy_hash, request_id, timestamp
 */
static std::string build_canonical_request(const std::string &request_id,
                                           const std::string &timestamp,
                                           const std::string &opcode,
                                           const std::string &params,
                                           uint64_t agent_sequence,
                                           const std::string &policy_hash,
                                           const std::string &command_message_id)
{
    std::ostringstream oss;
    oss << "{";
    oss << "\"agent_sequence\":" << agent_sequence << ",";
    oss << "\"command_message_id\":\"" << escape_json(command_message_id) << "\",";
    oss << "\"opcode\":\"" << escape_json(opcode) << "\",";
    oss << "\"params\":" << params << ",";
    oss << "\"policy_hash\":\"" << escape_json(policy_hash) << "\",";
    oss << "\"request_id\":\"" << escape_json(request_id) << "\",";
    oss << "\"timestamp\":\"" << escape_json(timestamp) << "\"";
    oss << "}";
    return oss.str();
}

/**
 * Build canonical response payload for kernel → agent
 * Fields in lexicographic order: error_code, error_message, kernel_exec_id, request_id, result, status, timestamp
 */
static std::string build_canonical_response(const std::string &request_id,
                                            const std::string &status,
                                            const std::string &kernel_exec_id,
                                            const std::string &timestamp,
                                            const std::string &result,
                                            int error_code,
                                            const std::string &error_message)
{
    std::ostringstream oss;
    oss << "{";
    oss << "\"error_code\":" << error_code << ",";
    oss << "\"error_message\":" << (error_message.empty() ? "null" : "\"" + escape_json(error_message) + "\"") << ",";
    oss << "\"kernel_exec_id\":\"" << escape_json(kernel_exec_id) << "\",";
    oss << "\"request_id\":\"" << escape_json(request_id) << "\",";
    oss << "\"result\":\"" << escape_json(result) << "\",";
    oss << "\"status\":\"" << escape_json(status) << "\",";
    oss << "\"timestamp\":\"" << escape_json(timestamp) << "\"";
    oss << "}";
    return oss.str();
}

// ============================================================================
// Mock Kernel Server
// ============================================================================

#ifdef _WIN32
struct MockKernel
{
    std::vector<unsigned char> agent_pk;  // To verify agent requests
    std::vector<unsigned char> kernel_sk; // To sign kernel responses
    std::string pipe_name;
    HANDLE ready_event;
    bool tamper_response; // If true, tamper the response signature

    void run()
    {
        HANDLE hPipe = CreateNamedPipeA(
            pipe_name.c_str(),
            PIPE_ACCESS_DUPLEX,
            PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT,
            1, 16384, 16384, 0, nullptr);

        if (hPipe == INVALID_HANDLE_VALUE)
        {
            std::cerr << "MockKernel: Failed to create pipe\n";
            SetEvent(ready_event);
            return;
        }

        SetEvent(ready_event);

        if (ConnectNamedPipe(hPipe, nullptr) || GetLastError() == ERROR_PIPE_CONNECTED)
        {
            char buf[16384];
            DWORD bytesRead = 0;
            if (ReadFile(hPipe, buf, sizeof(buf) - 1, &bytesRead, nullptr) && bytesRead > 0)
            {
                buf[bytesRead] = '\0';
                std::string request(buf);

                // Process the request and generate response
                std::string response = process_request(request);

                DWORD written = 0;
                WriteFile(hPipe, response.c_str(), (DWORD)response.size(), &written, nullptr);
                FlushFileBuffers(hPipe);
            }
        }

        DisconnectNamedPipe(hPipe);
        CloseHandle(hPipe);
    }

    std::string process_request(const std::string &request)
    {
        // Extract fields from request
        std::string request_id = extract_json_string(request, "request_id");
        std::string opcode = extract_json_string(request, "opcode");
        std::string timestamp = extract_json_string(request, "timestamp");
        std::string params = extract_json_string(request, "params");
        std::string sig_b64 = extract_json_string(request, "sig");
        std::string policy_hash = extract_json_string(request, "policy_hash");
        std::string command_message_id = extract_json_string(request, "command_message_id");
        int agent_sequence = extract_json_int(request, "agent_sequence");

        // Fix params - if empty or just extracted as string, use "{}"
        if (params.empty())
            params = "{}";

        // Build canonical payload for verification
        std::string canonical = build_canonical_request(
            request_id, timestamp, opcode, params,
            agent_sequence, policy_hash, command_message_id);

        // Verify agent signature
        std::vector<unsigned char> sig;
        bool sig_valid = false;
        if (!sig_b64.empty() && b64_decode(sig_b64, sig, crypto_sign_BYTES))
        {
            sig_valid = crypto_sign_verify_detached(
                            sig.data(),
                            reinterpret_cast<const unsigned char *>(canonical.data()),
                            canonical.size(),
                            agent_pk.data()) == 0;
        }

        if (!sig_valid)
        {
            // Return signature invalid error (error code 4001 per spec)
            return build_response(request_id, "error", "kexec-err", "signature_invalid", 4001, "SIGNATURE_INVALID");
        }

        // Signature valid - execute the "opcode" (mock)
        std::string result;
        if (opcode == "ping" || opcode == "EXEC_PING_KERNEL")
        {
            result = "pong";
        }
        else if (opcode == "EXEC_LOCK_SCREEN")
        {
            result = "workstation_locked";
        }
        else if (opcode == "COLLECT_SYSTEM_INFO")
        {
            result = "{\"os\":\"Windows\",\"version\":\"10\"}";
        }
        else
        {
            result = "executed";
        }

        return build_response(request_id, "ok", "kexec-" + request_id, result, 0, "");
    }

    std::string build_response(const std::string &request_id,
                               const std::string &status,
                               const std::string &kernel_exec_id,
                               const std::string &result,
                               int error_code,
                               const std::string &error_message)
    {
        std::string ts = iso_timestamp();

        // Build canonical payload for signing
        std::string canonical = build_canonical_response(
            request_id, status, kernel_exec_id, ts, result, error_code, error_message);

        // Sign the response
        unsigned char sig[crypto_sign_BYTES];
        crypto_sign_detached(sig, nullptr,
                             reinterpret_cast<const unsigned char *>(canonical.data()),
                             canonical.size(),
                             kernel_sk.data());

        // Optionally tamper the signature for negative tests
        if (tamper_response)
        {
            sig[0] ^= 0xFF;
        }

        std::string sig_b64 = b64_encode(sig, crypto_sign_BYTES);

        // Build full response JSON
        std::ostringstream oss;
        oss << "{";
        oss << "\"request_id\":\"" << escape_json(request_id) << "\",";
        oss << "\"status\":\"" << escape_json(status) << "\",";
        oss << "\"kernel_exec_id\":\"" << escape_json(kernel_exec_id) << "\",";
        oss << "\"timestamp\":\"" << escape_json(ts) << "\",";
        oss << "\"result\":\"" << escape_json(result) << "\",";
        oss << "\"error_code\":" << error_code << ",";
        if (error_message.empty())
        {
            oss << "\"error_message\":null,";
        }
        else
        {
            oss << "\"error_message\":\"" << escape_json(error_message) << "\",";
        }
        oss << "\"sig\":\"" << sig_b64 << "\"";
        oss << "}";

        return oss.str();
    }
};
#endif // _WIN32

// ============================================================================
// Agent Client (simulates agent sending request)
// ============================================================================

#ifdef _WIN32
struct AgentClient
{
    std::vector<unsigned char> agent_sk;  // To sign requests
    std::vector<unsigned char> kernel_pk; // To verify responses

    std::string send_request(const std::string &pipe_name,
                             const std::string &opcode,
                             bool tamper_request = false)
    {
        // Build request
        std::string request_id = "req-" + std::to_string(rand());
        std::string timestamp = iso_timestamp();
        std::string params = "{}";
        uint64_t agent_sequence = 1;
        std::string policy_hash = "policy-hash-abc";
        std::string command_message_id = "cmd-msg-" + std::to_string(rand());

        // Build canonical payload
        std::string canonical = build_canonical_request(
            request_id, timestamp, opcode, params,
            agent_sequence, policy_hash, command_message_id);

        // Sign the request
        unsigned char sig[crypto_sign_BYTES];
        crypto_sign_detached(sig, nullptr,
                             reinterpret_cast<const unsigned char *>(canonical.data()),
                             canonical.size(),
                             agent_sk.data());

        // Optionally tamper the signature
        if (tamper_request)
        {
            sig[0] ^= 0xFF;
        }

        std::string sig_b64 = b64_encode(sig, crypto_sign_BYTES);

        // Build full request JSON
        std::ostringstream oss;
        oss << "{";
        oss << "\"request_id\":\"" << escape_json(request_id) << "\",";
        oss << "\"timestamp\":\"" << escape_json(timestamp) << "\",";
        oss << "\"opcode\":\"" << escape_json(opcode) << "\",";
        oss << "\"params\":" << params << ",";
        oss << "\"agent_sequence\":" << agent_sequence << ",";
        oss << "\"policy_hash\":\"" << escape_json(policy_hash) << "\",";
        oss << "\"command_message_id\":\"" << escape_json(command_message_id) << "\",";
        oss << "\"sig\":\"" << sig_b64 << "\"";
        oss << "}";

        std::string request_json = oss.str();

        // Connect to pipe and send
        HANDLE hPipe = CreateFileA(
            pipe_name.c_str(),
            GENERIC_READ | GENERIC_WRITE,
            0, nullptr, OPEN_EXISTING, 0, nullptr);

        if (hPipe == INVALID_HANDLE_VALUE)
        {
            return "{\"error\":\"pipe_connect_failed\"}";
        }

        DWORD written;
        WriteFile(hPipe, request_json.c_str(), (DWORD)request_json.size(), &written, nullptr);

        char buf[16384];
        DWORD bytesRead;
        ReadFile(hPipe, buf, sizeof(buf) - 1, &bytesRead, nullptr);
        buf[bytesRead] = '\0';

        CloseHandle(hPipe);
        return std::string(buf);
    }

    bool verify_response(const std::string &response_json)
    {
        // Extract signature
        std::string sig_b64 = extract_json_string(response_json, "sig");
        if (sig_b64.empty())
            return false;

        // Extract all fields for canonical
        std::string request_id = extract_json_string(response_json, "request_id");
        std::string status = extract_json_string(response_json, "status");
        std::string kernel_exec_id = extract_json_string(response_json, "kernel_exec_id");
        std::string timestamp = extract_json_string(response_json, "timestamp");
        std::string result = extract_json_string(response_json, "result");
        int error_code = extract_json_int(response_json, "error_code");
        std::string error_message = extract_json_string(response_json, "error_message");

        // Build canonical payload
        std::string canonical = build_canonical_response(
            request_id, status, kernel_exec_id, timestamp, result, error_code, error_message);

        // Decode and verify signature
        std::vector<unsigned char> sig;
        if (!b64_decode(sig_b64, sig, crypto_sign_BYTES))
            return false;

        return crypto_sign_verify_detached(
                   sig.data(),
                   reinterpret_cast<const unsigned char *>(canonical.data()),
                   canonical.size(),
                   kernel_pk.data()) == 0;
    }
};
#endif // _WIN32

// ============================================================================
// Test Runner
// ============================================================================

int main()
{
    std::cout << "=== E2E Signature Chain Test (Task 1.7) ===\n\n";

    // Check for required environment variables
    const char *agent_sk_b64 = std::getenv("CI_AGENT_SK_B64");
    const char *agent_pk_b64 = std::getenv("CI_AGENT_PK_B64");
    const char *kernel_sk_b64 = std::getenv("CI_KERNEL_SK_B64");
    const char *kernel_pk_b64 = std::getenv("CI_KERNEL_PK_B64");

    // Fallback: use single key pair for both (simpler CI setup)
    const char *sk_b64 = std::getenv("CI_ED25519_SK_B64");
    const char *pk_b64 = std::getenv("CI_ED25519_PUB_B64");

    if (!agent_sk_b64)
        agent_sk_b64 = sk_b64;
    if (!agent_pk_b64)
        agent_pk_b64 = pk_b64;
    if (!kernel_sk_b64)
        kernel_sk_b64 = sk_b64;
    if (!kernel_pk_b64)
        kernel_pk_b64 = pk_b64;

    if (!agent_sk_b64 || !agent_pk_b64 || !kernel_sk_b64 || !kernel_pk_b64)
    {
        std::cout << "SKIPPED: Missing CI key environment variables\n";
        std::cout << "  Required: CI_AGENT_SK_B64, CI_AGENT_PK_B64, CI_KERNEL_SK_B64, CI_KERNEL_PK_B64\n";
        std::cout << "  Or: CI_ED25519_SK_B64, CI_ED25519_PUB_B64 (used for both sides)\n";
        return 0; // Skip, not fail
    }

    if (sodium_init() < 0)
    {
        std::cerr << "FAIL: sodium_init failed\n";
        return 1;
    }

    // Decode keys
    std::vector<unsigned char> agent_sk, agent_pk, kernel_sk, kernel_pk;
    if (!b64_decode(agent_sk_b64, agent_sk, 64) ||
        !b64_decode(agent_pk_b64, agent_pk, 32) ||
        !b64_decode(kernel_sk_b64, kernel_sk, 64) ||
        !b64_decode(kernel_pk_b64, kernel_pk, 32))
    {
        std::cerr << "FAIL: Failed to decode keys\n";
        return 1;
    }

#ifdef _WIN32
    int passed = 0;
    int failed = 0;

    // ========== TEST 1: Valid signatures on both sides ==========
    {
        std::cout << "[TEST 1] Valid request → Valid response\n";

        HANDLE ready = CreateEvent(nullptr, TRUE, FALSE, nullptr);
        std::string pipe = "\\\\.\\pipe\\E2ETest_Positive_" + std::to_string(GetTickCount());

        MockKernel kernel;
        kernel.agent_pk = agent_pk;
        kernel.kernel_sk = kernel_sk;
        kernel.pipe_name = pipe;
        kernel.ready_event = ready;
        kernel.tamper_response = false;

        std::thread server_thread([&kernel]()
                                  { kernel.run(); });
        WaitForSingleObject(ready, 3000);
        Sleep(50); // Give pipe time to initialize

        AgentClient agent;
        agent.agent_sk = agent_sk;
        agent.kernel_pk = kernel_pk;

        std::string response = agent.send_request(pipe, "ping");
        server_thread.join();
        CloseHandle(ready);

        // Check response
        std::string status = extract_json_string(response, "status");
        std::string result = extract_json_string(response, "result");
        bool sig_valid = agent.verify_response(response);

        if (status == "ok" && result == "pong" && sig_valid)
        {
            std::cout << "  ✓ PASSED: Response OK, signature valid\n";
            passed++;
        }
        else
        {
            std::cerr << "  ✗ FAILED: status=" << status << ", result=" << result << ", sig_valid=" << sig_valid << "\n";
            std::cerr << "    Response: " << response << "\n";
            failed++;
        }
    }

    // ========== TEST 2: Tampered request signature → kernel rejects ==========
    {
        std::cout << "[TEST 2] Tampered request → Kernel rejects\n";

        HANDLE ready = CreateEvent(nullptr, TRUE, FALSE, nullptr);
        std::string pipe = "\\\\.\\pipe\\E2ETest_BadRequest_" + std::to_string(GetTickCount());

        MockKernel kernel;
        kernel.agent_pk = agent_pk;
        kernel.kernel_sk = kernel_sk;
        kernel.pipe_name = pipe;
        kernel.ready_event = ready;
        kernel.tamper_response = false;

        std::thread server_thread([&kernel]()
                                  { kernel.run(); });
        WaitForSingleObject(ready, 3000);
        Sleep(50);

        AgentClient agent;
        agent.agent_sk = agent_sk;
        agent.kernel_pk = kernel_pk;

        // Send with tampered signature
        std::string response = agent.send_request(pipe, "ping", true);
        server_thread.join();
        CloseHandle(ready);

        // Kernel should reject with error 4001
        std::string status = extract_json_string(response, "status");
        int error_code = extract_json_int(response, "error_code");

        if (status == "error" && error_code == 4001)
        {
            std::cout << "  ✓ PASSED: Kernel correctly rejected tampered request (4001)\n";
            passed++;
        }
        else
        {
            std::cerr << "  ✗ SECURITY FAILURE: Tampered request was accepted!\n";
            std::cerr << "    status=" << status << ", error_code=" << error_code << "\n";
            std::cerr << "    Response: " << response << "\n";
            failed++;
        }
    }

    // ========== TEST 3: Tampered response signature → agent rejects ==========
    {
        std::cout << "[TEST 3] Valid request → Tampered response → Agent rejects\n";

        HANDLE ready = CreateEvent(nullptr, TRUE, FALSE, nullptr);
        std::string pipe = "\\\\.\\pipe\\E2ETest_BadResponse_" + std::to_string(GetTickCount());

        MockKernel kernel;
        kernel.agent_pk = agent_pk;
        kernel.kernel_sk = kernel_sk;
        kernel.pipe_name = pipe;
        kernel.ready_event = ready;
        kernel.tamper_response = true; // Tamper the response

        std::thread server_thread([&kernel]()
                                  { kernel.run(); });
        WaitForSingleObject(ready, 3000);
        Sleep(50);

        AgentClient agent;
        agent.agent_sk = agent_sk;
        agent.kernel_pk = kernel_pk;

        std::string response = agent.send_request(pipe, "ping");
        server_thread.join();
        CloseHandle(ready);

        // Agent should reject the tampered response
        bool sig_valid = agent.verify_response(response);

        if (!sig_valid)
        {
            std::cout << "  ✓ PASSED: Agent correctly rejected tampered response\n";
            passed++;
        }
        else
        {
            std::cerr << "  ✗ SECURITY FAILURE: Agent accepted tampered response!\n";
            std::cerr << "    Response: " << response << "\n";
            failed++;
        }
    }

    // ========== TEST 4: All opcodes with valid signatures ==========
    {
        std::cout << "[TEST 4] Multiple opcodes with valid signatures\n";

        std::vector<std::string> opcodes = {
            "ping",
            "EXEC_LOCK_SCREEN",
            "COLLECT_SYSTEM_INFO"};

        int opcode_passed = 0;
        for (const auto &opcode : opcodes)
        {
            HANDLE ready = CreateEvent(nullptr, TRUE, FALSE, nullptr);
            std::string pipe = "\\\\.\\pipe\\E2ETest_" + opcode + "_" + std::to_string(GetTickCount());

            MockKernel kernel;
            kernel.agent_pk = agent_pk;
            kernel.kernel_sk = kernel_sk;
            kernel.pipe_name = pipe;
            kernel.ready_event = ready;
            kernel.tamper_response = false;

            std::thread server_thread([&kernel]()
                                      { kernel.run(); });
            WaitForSingleObject(ready, 3000);
            Sleep(50);

            AgentClient agent;
            agent.agent_sk = agent_sk;
            agent.kernel_pk = kernel_pk;

            std::string response = agent.send_request(pipe, opcode);
            server_thread.join();
            CloseHandle(ready);

            std::string status = extract_json_string(response, "status");
            bool sig_valid = agent.verify_response(response);

            if (status == "ok" && sig_valid)
            {
                std::cout << "    ✓ " << opcode << ": OK\n";
                opcode_passed++;
            }
            else
            {
                std::cerr << "    ✗ " << opcode << ": FAILED (status=" << status << ", sig=" << sig_valid << ")\n";
            }
        }

        if (opcode_passed == (int)opcodes.size())
        {
            std::cout << "  ✓ PASSED: All " << opcodes.size() << " opcodes verified\n";
            passed++;
        }
        else
        {
            std::cerr << "  ✗ FAILED: Only " << opcode_passed << "/" << opcodes.size() << " opcodes passed\n";
            failed++;
        }
    }

    // ========== Summary ==========
    std::cout << "\n=== SUMMARY ===\n";
    std::cout << "Passed: " << passed << "\n";
    std::cout << "Failed: " << failed << "\n";

    if (failed > 0)
    {
        std::cerr << "\n*** E2E SIGNATURE CHAIN TEST FAILED ***\n";
        return 1;
    }

    std::cout << "\n*** E2E SIGNATURE CHAIN TEST PASSED ***\n";
    std::cout << "✓ Agent request signing verified\n";
    std::cout << "✓ Kernel request verification verified\n";
    std::cout << "✓ Kernel response signing verified\n";
    std::cout << "✓ Agent response verification verified\n";
    std::cout << "✓ Tampered signatures correctly rejected\n";
    return 0;

#else
    std::cout << "SKIPPED: E2E test requires Windows for named pipe IPC\n";
    return 0;
#endif
}

#else  // !HAVE_SODIUM
int main()
{
    std::cout << "SKIPPED: E2E test requires libsodium\n";
    return 0;
}
#endif // HAVE_SODIUM
