#include "telemetry_http_client.hpp"

#ifdef _WIN32
#include <windows.h>
#include <winhttp.h>
#pragma comment(lib, "winhttp.lib")
#endif

#include <string>
#include <vector>

namespace
{
#ifdef _WIN32
std::wstring utf8_to_wide(const std::string &s)
{
    if (s.empty())
    {
        return {};
    }
    const int size = MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, nullptr, 0);
    if (size <= 1)
    {
        return {};
    }
    std::wstring out(static_cast<std::size_t>(size - 1), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, s.c_str(), -1, out.data(), size);
    return out;
}

std::string wide_to_utf8(const std::wstring &s)
{
    if (s.empty())
    {
        return {};
    }
    const int size = WideCharToMultiByte(CP_UTF8, 0, s.c_str(), -1, nullptr, 0, nullptr, nullptr);
    if (size <= 1)
    {
        return {};
    }
    std::string out(static_cast<std::size_t>(size - 1), '\0');
    WideCharToMultiByte(CP_UTF8, 0, s.c_str(), -1, out.data(), size, nullptr, nullptr);
    return out;
}
#endif
} // namespace

TelemetryHttpResponse TelemetryHttpClient::post_json(
    const std::string &url,
    const std::string &bearer_jwt,
    const std::string &body_json,
    std::uint32_t timeout_ms) const
{
    TelemetryHttpResponse out;
#ifndef _WIN32
    out.error_reason = "unsupported_platform";
    return out;
#else
    const std::wstring wurl = utf8_to_wide(url);
    if (wurl.empty())
    {
        out.error_reason = "invalid_url";
        return out;
    }

    URL_COMPONENTS parts{};
    parts.dwStructSize = sizeof(parts);
    parts.dwSchemeLength = static_cast<DWORD>(-1);
    parts.dwHostNameLength = static_cast<DWORD>(-1);
    parts.dwUrlPathLength = static_cast<DWORD>(-1);
    parts.dwExtraInfoLength = static_cast<DWORD>(-1);
    if (!WinHttpCrackUrl(wurl.c_str(), 0, 0, &parts))
    {
        out.error_reason = "invalid_url";
        return out;
    }

    const std::wstring host(parts.lpszHostName, parts.dwHostNameLength);
    std::wstring path(parts.lpszUrlPath && parts.dwUrlPathLength ? parts.lpszUrlPath : L"/",
                      parts.dwUrlPathLength ? parts.dwUrlPathLength : 1);
    if (parts.dwExtraInfoLength > 0 && parts.lpszExtraInfo)
    {
        path.append(parts.lpszExtraInfo, parts.dwExtraInfoLength);
    }

    const bool secure = (parts.nScheme == INTERNET_SCHEME_HTTPS);

    HINTERNET h_session = WinHttpOpen(
        L"QuoodleAgent/1.0",
        WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
        WINHTTP_NO_PROXY_NAME,
        WINHTTP_NO_PROXY_BYPASS,
        0);
    if (!h_session)
    {
        out.error_reason = "session_open_failed";
        return out;
    }

    WinHttpSetTimeouts(
        h_session,
        static_cast<int>(timeout_ms),
        static_cast<int>(timeout_ms),
        static_cast<int>(timeout_ms),
        static_cast<int>(timeout_ms));

    HINTERNET h_connect = WinHttpConnect(h_session, host.c_str(), parts.nPort, 0);
    if (!h_connect)
    {
        WinHttpCloseHandle(h_session);
        out.error_reason = "connect_failed";
        return out;
    }

    const DWORD flags = secure ? WINHTTP_FLAG_SECURE : 0;
    HINTERNET h_request = WinHttpOpenRequest(
        h_connect,
        L"POST",
        path.c_str(),
        nullptr,
        WINHTTP_NO_REFERER,
        WINHTTP_DEFAULT_ACCEPT_TYPES,
        flags);

    if (!h_request)
    {
        WinHttpCloseHandle(h_connect);
        WinHttpCloseHandle(h_session);
        out.error_reason = "request_open_failed";
        return out;
    }

    std::wstring headers = L"Content-Type: application/json\r\n";
    if (!bearer_jwt.empty())
    {
        headers += L"Authorization: Bearer " + utf8_to_wide(bearer_jwt) + L"\r\n";
    }

    BOOL sent = WinHttpSendRequest(
        h_request,
        headers.c_str(),
        static_cast<DWORD>(-1),
        body_json.empty() ? WINHTTP_NO_REQUEST_DATA : const_cast<char *>(body_json.data()),
        static_cast<DWORD>(body_json.size()),
        static_cast<DWORD>(body_json.size()),
        0);
    if (!sent)
    {
        out.error_reason = "send_failed";
        WinHttpCloseHandle(h_request);
        WinHttpCloseHandle(h_connect);
        WinHttpCloseHandle(h_session);
        return out;
    }

    if (!WinHttpReceiveResponse(h_request, nullptr))
    {
        out.error_reason = "receive_failed";
        WinHttpCloseHandle(h_request);
        WinHttpCloseHandle(h_connect);
        WinHttpCloseHandle(h_session);
        return out;
    }

    DWORD status_code = 0;
    DWORD status_code_size = sizeof(status_code);
    WinHttpQueryHeaders(
        h_request,
        WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
        WINHTTP_HEADER_NAME_BY_INDEX,
        &status_code,
        &status_code_size,
        WINHTTP_NO_HEADER_INDEX);
    out.status_code = static_cast<int>(status_code);

    std::string response_body;
    DWORD bytes_available = 0;
    do
    {
        bytes_available = 0;
        if (!WinHttpQueryDataAvailable(h_request, &bytes_available))
        {
            break;
        }
        if (bytes_available == 0)
        {
            break;
        }

        std::vector<char> buffer(bytes_available + 1, 0);
        DWORD bytes_read = 0;
        if (!WinHttpReadData(h_request, buffer.data(), bytes_available, &bytes_read))
        {
            break;
        }
        response_body.append(buffer.data(), bytes_read);
    } while (bytes_available > 0);
    out.body = std::move(response_body);

    out.ok = (out.status_code >= 200 && out.status_code < 300);
    if (!out.ok && out.error_reason.empty())
    {
        out.error_reason = "http_" + std::to_string(out.status_code);
    }

    WinHttpCloseHandle(h_request);
    WinHttpCloseHandle(h_connect);
    WinHttpCloseHandle(h_session);
    return out;
#endif
}

