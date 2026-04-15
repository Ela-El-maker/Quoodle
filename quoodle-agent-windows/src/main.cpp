#include <atomic>
#include <csignal>
#include <cstdlib>
#include <string>
#include <thread>
#include <memory>
#include <algorithm>
#include <cctype>
#include <mutex>
#include <chrono>
#include <cstdio>

#ifdef _WIN32
#include <windows.h>
#include "control/ui_bridge_server.hpp"
#endif

#include "ws/ws_client.hpp"
#include "config/config_manager.hpp"
#include "comm/communicator.hpp"
#include "command/screenshot_helper.hpp"
#include "crypto/ed25519_sign.hpp"
#include "logging/logger.hpp"

// Global communicator pointer for signal handler
static std::atomic<Communicator *> g_communicator{nullptr};
static std::mutex g_runtime_meta_mutex;
static std::string g_last_endpoint;
static std::string g_last_device_id;
static std::string g_last_agent_pubkey;

#ifdef _WIN32
static std::atomic<bool> g_running_as_service{false};
static std::unique_ptr<control::UiBridgeServer> g_ui_bridge_server;
static constexpr const char *kGlobalInstanceMutexName = "Global\\QuoodleAgentSingleton";
static constexpr const char *kLocalInstanceMutexName = "Local\\QuoodleAgentSingleton";

static std::string now_iso_utc()
{
    using namespace std::chrono;
    const auto now = system_clock::now();
    const auto tt = system_clock::to_time_t(now);
    std::tm tm{};
    gmtime_s(&tm, &tt);
    char buffer[64];
    std::snprintf(buffer, sizeof(buffer), "%04d-%02d-%02dT%02d:%02d:%02dZ",
                  tm.tm_year + 1900, tm.tm_mon + 1, tm.tm_mday,
                  tm.tm_hour, tm.tm_min, tm.tm_sec);
    return std::string(buffer);
}

static std::string connection_state_to_string(ConnectionState state)
{
    switch (state)
    {
    case ConnectionState::Connected:
        return "connected";
    case ConnectionState::Connecting:
        return "connecting";
    case ConnectionState::Reconnecting:
        return "reconnecting";
    case ConnectionState::Failed:
        return "failed";
    case ConnectionState::Shutdown:
        return "shutdown";
    case ConnectionState::Disconnected:
    default:
        return "disconnected";
    }
}

static control::UiBridgeStatus read_ui_bridge_status()
{
    control::UiBridgeStatus status{};
    status.service_mode = g_running_as_service.load(std::memory_order_acquire);
    status.timestamp_utc = now_iso_utc();
    {
        std::lock_guard<std::mutex> guard(g_runtime_meta_mutex);
        status.endpoint = g_last_endpoint;
        status.device_id = g_last_device_id;
        status.agent_pubkey_b64 = g_last_agent_pubkey;
    }

    if (auto *comm = g_communicator.load(std::memory_order_acquire))
    {
        status.communicator_present = true;
        status.connected = comm->is_connected();
        status.connection_state = connection_state_to_string(comm->state());
        status.reconnect_attempts = comm->reconnect_attempts();
    }
    else
    {
        status.communicator_present = false;
        status.connected = false;
        status.connection_state = "disconnected";
        status.reconnect_attempts = 0;
    }
    return status;
}

static bool ui_bridge_sync_now(std::string &reason_out)
{
    if (auto *comm = g_communicator.load(std::memory_order_acquire))
    {
        comm->request_sync_now();
        reason_out.clear();
        return true;
    }
    reason_out = "communicator_unavailable";
    return false;
}

static bool ui_bridge_reconnect(std::string &reason_out)
{
    if (auto *comm = g_communicator.load(std::memory_order_acquire))
    {
        comm->request_reconnect();
        reason_out.clear();
        return true;
    }
    reason_out = "communicator_unavailable";
    return false;
}

static void start_ui_bridge_server()
{
    if (g_ui_bridge_server)
    {
        return;
    }
    g_ui_bridge_server = std::make_unique<control::UiBridgeServer>(
        read_ui_bridge_status,
        ui_bridge_sync_now,
        ui_bridge_reconnect);
    if (!g_ui_bridge_server->start())
    {
        g_ui_bridge_server.reset();
    }
}

static void stop_ui_bridge_server()
{
    if (g_ui_bridge_server)
    {
        g_ui_bridge_server->stop();
        g_ui_bridge_server.reset();
    }
}

static bool allow_multi_instance()
{
    const char *raw = std::getenv("AGENT_ALLOW_MULTI_INSTANCE");
    if (!raw || !*raw)
    {
        return false;
    }
    std::string value(raw);
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char ch)
                   { return static_cast<char>(std::tolower(ch)); });
    return value == "1" || value == "true" || value == "yes" || value == "on";
}

static HANDLE try_create_instance_mutex(const char *name, DWORD &last_error_out)
{
    SetLastError(ERROR_SUCCESS);
    HANDLE handle = CreateMutexExA(nullptr, name, 0, SYNCHRONIZE | MUTEX_MODIFY_STATE);
    last_error_out = GetLastError();
    return handle;
}
#endif

static void signal_handler(int signal)
{
    if (auto *comm = g_communicator.load(std::memory_order_acquire))
    {
        Logger::log(LogLevel::Info, "received signal " + std::to_string(signal) + ", shutting down...");
        comm->shutdown();
    }
}

static std::unique_ptr<Communicator> build_communicator()
{
    AgentConfig cfg = ConfigManager::load_from_env();

    const auto activePubkey = ed25519_active_public_key_b64();
    if (activePubkey.empty())
    {
        Logger::log(LogLevel::Error, "Unable to derive Ed25519 signing public key from runtime private key.");
        return nullptr;
    }

    {
        std::lock_guard<std::mutex> guard(g_runtime_meta_mutex);
        g_last_endpoint = cfg.endpoint;
        g_last_device_id = cfg.device_id;
        g_last_agent_pubkey = activePubkey;
    }

    if (cfg.jwt.empty())
    {
        Logger::log(LogLevel::Error, "Missing AGENT_JWT environment variable; cannot build AUTH message.");
        return nullptr;
    }

    Logger::log(LogLevel::Info, "Agent signing pubkey: " + activePubkey);

    if (const char *expected = std::getenv("AGENT_EXPECTED_PUBKEY_B64"); expected && *expected)
    {
        std::string expectedPubkey(expected);
        expectedPubkey.erase(
            std::remove_if(expectedPubkey.begin(), expectedPubkey.end(),
                           [](unsigned char ch) { return std::isspace(ch) != 0; }),
            expectedPubkey.end());
        if (expectedPubkey != activePubkey)
        {
            Logger::log(LogLevel::Error, "Agent signing pubkey mismatch. expected=" + expectedPubkey + " actual=" + activePubkey);
            return nullptr;
        }
        Logger::log(LogLevel::Info, "Agent signing pubkey matches expected paired key.");
    }

    auto comm = std::make_unique<Communicator>(cfg);

    comm->on_state_change([](ConnectionState state, const std::string &reason)
                         {
        std::string state_str;
        switch (state) {
            case ConnectionState::Connected:
                state_str = "CONNECTED";
                break;
            case ConnectionState::Reconnecting:
                state_str = "RECONNECTING";
                break;
            case ConnectionState::Failed:
                state_str = "FAILED";
                break;
            default:
                return; // Don't log other states
        }
        Logger::log(LogLevel::Info, "Connection: " + state_str + 
                    (reason.empty() ? "" : " - " + reason)); });

    Logger::log(LogLevel::Info, "Endpoint: " + cfg.endpoint);
    Logger::log(LogLevel::Info, "Device ID: " + cfg.device_id);
    return comm;
}

static int run_console_mode()
{
    Logger::log(LogLevel::Info, "Quoodle Agent starting in console mode...");
    g_running_as_service.store(false, std::memory_order_release);
    start_ui_bridge_server();
    auto comm = build_communicator();
    if (!comm)
    {
        stop_ui_bridge_server();
        return 1;
    }

    g_communicator.store(comm.get(), std::memory_order_release);
    std::signal(SIGINT, signal_handler);
    std::signal(SIGTERM, signal_handler);

    Logger::log(LogLevel::Info, "Starting WebSocket client with reconnection support");
    comm->start();

    g_communicator.store(nullptr, std::memory_order_release);
    stop_ui_bridge_server();
    Logger::log(LogLevel::Info, "Quoodle Agent stopped (console mode)");
    return 0;
}

#ifdef _WIN32
static constexpr DWORD kServiceAcceptMask = SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN;
static constexpr DWORD kServiceRestartDelayMs = 5000;
static constexpr DWORD kServiceConfigRetryDelayMs = 15000;
static constexpr const char* kServiceName = "QuoodleAgent";
static SERVICE_STATUS_HANDLE g_service_status_handle = nullptr;
static SERVICE_STATUS g_service_status{};
static HANDLE g_service_stop_event = nullptr;
static std::atomic<bool> g_service_stop_requested{false};
static std::thread g_service_worker;

static void set_service_status(DWORD state, DWORD win32_exit_code, DWORD wait_hint)
{
    g_service_status.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
    g_service_status.dwCurrentState = state;
    g_service_status.dwWin32ExitCode = win32_exit_code;
    g_service_status.dwWaitHint = wait_hint;
    g_service_status.dwControlsAccepted =
        (state == SERVICE_RUNNING) ? kServiceAcceptMask : 0;
    g_service_status.dwCheckPoint =
        (state == SERVICE_START_PENDING || state == SERVICE_STOP_PENDING) ? 1 : 0;

    if (g_service_status_handle)
    {
        SetServiceStatus(g_service_status_handle, &g_service_status);
    }
}

static DWORD WINAPI service_ctrl_handler(DWORD control, DWORD, LPVOID, LPVOID)
{
    switch (control)
    {
    case SERVICE_CONTROL_STOP:
    case SERVICE_CONTROL_SHUTDOWN:
        Logger::log(LogLevel::Info, "Service stop control received");
        set_service_status(SERVICE_STOP_PENDING, NO_ERROR, 15000);
        g_service_stop_requested.store(true, std::memory_order_release);
        if (auto *comm = g_communicator.load(std::memory_order_acquire))
        {
            comm->shutdown();
        }
        if (g_service_stop_event)
        {
            SetEvent(g_service_stop_event);
        }
        return NO_ERROR;
    default:
        return ERROR_CALL_NOT_IMPLEMENTED;
    }
}

static VOID WINAPI service_main(DWORD, LPSTR *)
{
    g_service_status_handle = RegisterServiceCtrlHandlerExA(kServiceName, service_ctrl_handler, nullptr);
    if (!g_service_status_handle)
    {
        return;
    }

    g_service_stop_requested.store(false, std::memory_order_release);
    g_running_as_service.store(true, std::memory_order_release);
    set_service_status(SERVICE_START_PENDING, NO_ERROR, 10000);
    g_service_stop_event = CreateEventA(nullptr, TRUE, FALSE, nullptr);
    if (!g_service_stop_event)
    {
        set_service_status(SERVICE_STOPPED, GetLastError(), 0);
        return;
    }

    Logger::log(LogLevel::Info, "Quoodle Agent starting in Windows service mode...");
    start_ui_bridge_server();
    g_service_worker = std::thread([]()
                                   {
        while (!g_service_stop_requested.load(std::memory_order_acquire)) {
            auto comm = build_communicator();
            if (!comm) {
                Logger::log(LogLevel::Error, "Service communicator init failed; retrying");
                if (WaitForSingleObject(g_service_stop_event, kServiceConfigRetryDelayMs) == WAIT_OBJECT_0) {
                    break;
                }
                continue;
            }

            g_communicator.store(comm.get(), std::memory_order_release);
            Logger::log(LogLevel::Info, "Service communicator loop started");
            comm->start();
            g_communicator.store(nullptr, std::memory_order_release);

            if (g_service_stop_requested.load(std::memory_order_acquire)) {
                break;
            }

            Logger::log(LogLevel::Warn, "Communicator loop exited unexpectedly; restarting");
            if (WaitForSingleObject(g_service_stop_event, kServiceRestartDelayMs) == WAIT_OBJECT_0) {
                break;
            }
        } });

    set_service_status(SERVICE_RUNNING, NO_ERROR, 0);
    WaitForSingleObject(g_service_stop_event, INFINITE);

    if (auto *comm = g_communicator.load(std::memory_order_acquire))
    {
        comm->shutdown();
    }
    if (g_service_worker.joinable())
    {
        g_service_worker.join();
    }

    g_service_stop_requested.store(false, std::memory_order_release);
    g_running_as_service.store(false, std::memory_order_release);
    g_communicator.store(nullptr, std::memory_order_release);
    stop_ui_bridge_server();

    CloseHandle(g_service_stop_event);
    g_service_stop_event = nullptr;
    set_service_status(SERVICE_STOPPED, NO_ERROR, 0);
    Logger::log(LogLevel::Info, "Quoodle Agent stopped (service mode)");
}

static bool try_run_service_dispatcher()
{
    SERVICE_TABLE_ENTRYA table[] = {
        {const_cast<LPSTR>(kServiceName), service_main},
        {nullptr, nullptr}};

    if (!StartServiceCtrlDispatcherA(table))
    {
        DWORD err = GetLastError();
        if (err == ERROR_FAILED_SERVICE_CONTROLLER_CONNECT)
        {
            return false;
        }

        Logger::log(LogLevel::Error, "StartServiceCtrlDispatcher failed: " + std::to_string(err));
        return false;
    }
    return true;
}
#endif

int main(int argc, char **argv)
{
    const int helper_mode_rc = command::TryRunScreenshotHelper(argc, argv);
    if (helper_mode_rc >= 0)
    {
        return helper_mode_rc;
    }

#ifdef _WIN32
    DWORD mutex_last_error = ERROR_SUCCESS;
    const char *mutex_name = kGlobalInstanceMutexName;
    HANDLE instance_mutex = try_create_instance_mutex(mutex_name, mutex_last_error);
    if (!instance_mutex && mutex_last_error == ERROR_ACCESS_DENIED)
    {
        Logger::log(LogLevel::Warn, "Global single-instance mutex access denied; retrying in Local namespace.");
        mutex_name = kLocalInstanceMutexName;
        instance_mutex = try_create_instance_mutex(mutex_name, mutex_last_error);
    }

    if (!instance_mutex)
    {
        Logger::log(LogLevel::Error, "Failed to create single-instance mutex (" + std::string(mutex_name) + "): " + std::to_string(mutex_last_error));
        return 1;
    }
    if (mutex_last_error == ERROR_ALREADY_EXISTS && !allow_multi_instance())
    {
        Logger::log(LogLevel::Warn, "Another Quoodle agent instance is already running. Exiting this process.");
        CloseHandle(instance_mutex);
        return 2;
    }

    bool force_console = false;
    bool force_service = false;

    for (int i = 1; i < argc; ++i)
    {
        std::string arg = argv[i] ? argv[i] : "";
        if (arg == "--console")
        {
            force_console = true;
        }
        else if (arg == "--service")
        {
            force_service = true;
        }
    }

    if (force_console)
    {
        const int rc = run_console_mode();
        CloseHandle(instance_mutex);
        return rc;
    }

    if (force_service)
    {
        if (try_run_service_dispatcher())
        {
            CloseHandle(instance_mutex);
            return 0;
        }
        CloseHandle(instance_mutex);
        return 1;
    }

    if (try_run_service_dispatcher())
    {
        CloseHandle(instance_mutex);
        return 0;
    }

    const int rc = run_console_mode();
    CloseHandle(instance_mutex);
    return rc;
#endif

    return run_console_mode();
}
