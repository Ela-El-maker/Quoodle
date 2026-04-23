#include "artifact_client.hpp"

#include "../telemetry/telemetry_http_client.hpp"

#include <nlohmann/json.hpp>

#include <filesystem>
#include <fstream>
#include <vector>

#ifdef _WIN32
#include <windows.h>
#include <winhttp.h>
#pragma comment(lib, "winhttp.lib")
#endif

namespace command
{
namespace
{

std::string trim_trailing_slash(std::string url)
{
  while (!url.empty() && url.back() == '/')
  {
    url.pop_back();
  }
  return url;
}

std::string content_type_for_path(const std::string &path)
{
  const std::filesystem::path file_path(path);
  const std::string ext = file_path.has_extension() ? file_path.extension().string() : "";
  if (ext == ".png")
  {
    return "image/png";
  }
  if (ext == ".jpg" || ext == ".jpeg")
  {
    return "image/jpeg";
  }
  return "application/octet-stream";
}

bool read_file_binary(const std::string &path, std::vector<char> &out_bytes)
{
  std::ifstream file(path, std::ios::binary);
  if (!file)
  {
    return false;
  }
  file.seekg(0, std::ios::end);
  const auto size = file.tellg();
  if (size <= 0)
  {
    return false;
  }
  const auto stream_size = static_cast<std::streamsize>(size);
  out_bytes.resize(static_cast<size_t>(stream_size));
  file.seekg(0, std::ios::beg);
  file.read(out_bytes.data(), stream_size);
  return static_cast<bool>(file);
}

bool ensure_parent_directory(const std::string &path)
{
  const std::filesystem::path file_path(path);
  const auto parent = file_path.parent_path();
  if (parent.empty())
  {
    return true;
  }

  std::error_code ec;
  if (std::filesystem::exists(parent, ec))
  {
    return std::filesystem::is_directory(parent, ec);
  }
  return std::filesystem::create_directories(parent, ec);
}

#ifdef _WIN32
std::wstring utf8_to_wide(const std::string &input)
{
  if (input.empty())
  {
    return {};
  }
  const int size = MultiByteToWideChar(CP_UTF8, 0, input.c_str(), -1, nullptr, 0);
  if (size <= 1)
  {
    return {};
  }
  std::wstring out(static_cast<size_t>(size - 1), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, input.c_str(), -1, out.data(), size);
  return out;
}

ArtifactUploadResult upload_multipart_winhttp(
    const std::string &url,
    const std::string &bearer_jwt,
    const std::string &artifact_id,
    const std::string &upload_token,
    const std::string &file_path,
    std::uint32_t timeout_ms)
{
  ArtifactUploadResult out{};

  std::vector<char> file_bytes;
  if (!read_file_binary(file_path, file_bytes))
  {
    out.reason = "upload_file_read_failed";
    return out;
  }

  const std::string boundary = "----QuoodleBoundary7MA4YWxkTrZu0gW";
  const std::string file_name = std::filesystem::path(file_path).filename().string();
  const std::string content_type = content_type_for_path(file_path);

  std::string body;
  body.reserve(file_bytes.size() + 1024);
  body.append("--").append(boundary).append("\r\n");
  body.append("Content-Disposition: form-data; name=\"artifact_id\"\r\n\r\n");
  body.append(artifact_id).append("\r\n");

  body.append("--").append(boundary).append("\r\n");
  body.append("Content-Disposition: form-data; name=\"upload_token\"\r\n\r\n");
  body.append(upload_token).append("\r\n");

  body.append("--").append(boundary).append("\r\n");
  body.append("Content-Disposition: form-data; name=\"artifact\"; filename=\"").append(file_name).append("\"\r\n");
  body.append("Content-Type: ").append(content_type).append("\r\n\r\n");
  body.append(file_bytes.data(), file_bytes.size());
  body.append("\r\n--").append(boundary).append("--\r\n");

  const std::wstring wurl = utf8_to_wide(url);
  if (wurl.empty())
  {
    out.reason = "upload_invalid_url";
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
    out.reason = "upload_invalid_url";
    return out;
  }

  const bool secure = parts.nScheme == INTERNET_SCHEME_HTTPS;
  const std::wstring host(parts.lpszHostName, parts.dwHostNameLength);
  std::wstring path(
      parts.lpszUrlPath && parts.dwUrlPathLength ? parts.lpszUrlPath : L"/",
      parts.dwUrlPathLength ? parts.dwUrlPathLength : 1);
  if (parts.dwExtraInfoLength > 0 && parts.lpszExtraInfo)
  {
    path.append(parts.lpszExtraInfo, parts.dwExtraInfoLength);
  }

  HINTERNET session = WinHttpOpen(
      L"QuoodleAgent/1.0",
      WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
      WINHTTP_NO_PROXY_NAME,
      WINHTTP_NO_PROXY_BYPASS,
      0);
  if (!session)
  {
    out.reason = "upload_session_open_failed";
    return out;
  }
  WinHttpSetTimeouts(session, static_cast<int>(timeout_ms), static_cast<int>(timeout_ms),
                     static_cast<int>(timeout_ms), static_cast<int>(timeout_ms));

  HINTERNET connect = WinHttpConnect(session, host.c_str(), parts.nPort, 0);
  if (!connect)
  {
    WinHttpCloseHandle(session);
    out.reason = "upload_connect_failed";
    return out;
  }

  HINTERNET request = WinHttpOpenRequest(
      connect,
      L"POST",
      path.c_str(),
      nullptr,
      WINHTTP_NO_REFERER,
      WINHTTP_DEFAULT_ACCEPT_TYPES,
      secure ? WINHTTP_FLAG_SECURE : 0);
  if (!request)
  {
    WinHttpCloseHandle(connect);
    WinHttpCloseHandle(session);
    out.reason = "upload_request_open_failed";
    return out;
  }

  std::wstring headers = L"Content-Type: multipart/form-data; boundary=" + utf8_to_wide(boundary) + L"\r\n";
  if (!bearer_jwt.empty())
  {
    headers += L"Authorization: Bearer " + utf8_to_wide(bearer_jwt) + L"\r\n";
  }

  BOOL sent = WinHttpSendRequest(
      request,
      headers.c_str(),
      static_cast<DWORD>(-1),
      body.empty() ? WINHTTP_NO_REQUEST_DATA : const_cast<char *>(body.data()),
      static_cast<DWORD>(body.size()),
      static_cast<DWORD>(body.size()),
      0);
  if (!sent || !WinHttpReceiveResponse(request, nullptr))
  {
    WinHttpCloseHandle(request);
    WinHttpCloseHandle(connect);
    WinHttpCloseHandle(session);
    out.reason = "upload_send_failed";
    return out;
  }

  DWORD status_code = 0;
  DWORD status_size = sizeof(status_code);
  WinHttpQueryHeaders(
      request,
      WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
      WINHTTP_HEADER_NAME_BY_INDEX,
      &status_code,
      &status_size,
      WINHTTP_NO_HEADER_INDEX);

  std::string response_body;
  DWORD bytes_available = 0;
  do
  {
    bytes_available = 0;
    if (!WinHttpQueryDataAvailable(request, &bytes_available) || bytes_available == 0)
    {
      break;
    }
    std::vector<char> buffer(bytes_available + 1, 0);
    DWORD bytes_read = 0;
    if (!WinHttpReadData(request, buffer.data(), bytes_available, &bytes_read))
    {
      break;
    }
    response_body.append(buffer.data(), bytes_read);
  } while (bytes_available > 0);

  WinHttpCloseHandle(request);
  WinHttpCloseHandle(connect);
  WinHttpCloseHandle(session);

  if (status_code < 200 || status_code >= 300)
  {
    out.reason = "upload_http_" + std::to_string(status_code);
    return out;
  }

  try
  {
    const auto parsed = nlohmann::json::parse(response_body);
    if (parsed.value("status", "") != "stored")
    {
      out.reason = "upload_rejected";
      return out;
    }
    out.artifact_url = parsed.value("artifact_url", "");
    out.artifact_checksum = parsed.value("artifact_checksum", "");
    if (out.artifact_url.empty() || out.artifact_checksum.empty())
    {
      out.reason = "upload_response_missing_fields";
      return out;
    }
  }
  catch (const std::exception &)
  {
    out.reason = "upload_parse_failed";
    return out;
  }

  out.ok = true;
  return out;
}

ArtifactDownloadResult download_to_file_winhttp(
    const std::string &url,
    const std::string &bearer_jwt,
    const std::string &output_path,
    std::uint32_t timeout_ms)
{
  ArtifactDownloadResult out{};
  const std::wstring wurl = utf8_to_wide(url);
  if (wurl.empty())
  {
    out.reason = "artifact_download_invalid_url";
    return out;
  }

  if (!ensure_parent_directory(output_path))
  {
    out.reason = "artifact_download_create_parent_failed";
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
    out.reason = "artifact_download_invalid_url";
    return out;
  }

  const bool secure = parts.nScheme == INTERNET_SCHEME_HTTPS;
  const std::wstring host(parts.lpszHostName, parts.dwHostNameLength);
  std::wstring path(
      parts.lpszUrlPath && parts.dwUrlPathLength ? parts.lpszUrlPath : L"/",
      parts.dwUrlPathLength ? parts.dwUrlPathLength : 1);
  if (parts.dwExtraInfoLength > 0 && parts.lpszExtraInfo)
  {
    path.append(parts.lpszExtraInfo, parts.dwExtraInfoLength);
  }

  HINTERNET session = WinHttpOpen(
      L"QuoodleAgent/1.0",
      WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY,
      WINHTTP_NO_PROXY_NAME,
      WINHTTP_NO_PROXY_BYPASS,
      0);
  if (!session)
  {
    out.reason = "artifact_download_session_open_failed";
    return out;
  }
  WinHttpSetTimeouts(session, static_cast<int>(timeout_ms), static_cast<int>(timeout_ms),
                     static_cast<int>(timeout_ms), static_cast<int>(timeout_ms));

  HINTERNET connect = WinHttpConnect(session, host.c_str(), parts.nPort, 0);
  if (!connect)
  {
    WinHttpCloseHandle(session);
    out.reason = "artifact_download_connect_failed";
    return out;
  }

  HINTERNET request = WinHttpOpenRequest(
      connect,
      L"GET",
      path.c_str(),
      nullptr,
      WINHTTP_NO_REFERER,
      WINHTTP_DEFAULT_ACCEPT_TYPES,
      secure ? WINHTTP_FLAG_SECURE : 0);
  if (!request)
  {
    WinHttpCloseHandle(connect);
    WinHttpCloseHandle(session);
    out.reason = "artifact_download_request_open_failed";
    return out;
  }

  std::wstring headers;
  if (!bearer_jwt.empty())
  {
    headers += L"Authorization: Bearer " + utf8_to_wide(bearer_jwt) + L"\r\n";
  }

  BOOL sent = WinHttpSendRequest(
      request,
      headers.empty() ? WINHTTP_NO_ADDITIONAL_HEADERS : headers.c_str(),
      headers.empty() ? 0 : static_cast<DWORD>(-1),
      WINHTTP_NO_REQUEST_DATA,
      0,
      0,
      0);
  if (!sent || !WinHttpReceiveResponse(request, nullptr))
  {
    WinHttpCloseHandle(request);
    WinHttpCloseHandle(connect);
    WinHttpCloseHandle(session);
    out.reason = "artifact_download_send_failed";
    return out;
  }

  DWORD status_code = 0;
  DWORD status_size = sizeof(status_code);
  WinHttpQueryHeaders(
      request,
      WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
      WINHTTP_HEADER_NAME_BY_INDEX,
      &status_code,
      &status_size,
      WINHTTP_NO_HEADER_INDEX);

  if (status_code < 200 || status_code >= 300)
  {
    WinHttpCloseHandle(request);
    WinHttpCloseHandle(connect);
    WinHttpCloseHandle(session);
    out.reason = "artifact_download_http_" + std::to_string(status_code);
    return out;
  }

  std::ofstream output(output_path, std::ios::binary | std::ios::trunc);
  if (!output.is_open())
  {
    WinHttpCloseHandle(request);
    WinHttpCloseHandle(connect);
    WinHttpCloseHandle(session);
    out.reason = "artifact_download_output_open_failed";
    return out;
  }

  DWORD bytes_available = 0;
  std::uint64_t total_written = 0;
  do
  {
    bytes_available = 0;
    if (!WinHttpQueryDataAvailable(request, &bytes_available) || bytes_available == 0)
    {
      break;
    }
    std::vector<char> buffer(bytes_available, 0);
    DWORD bytes_read = 0;
    if (!WinHttpReadData(request, buffer.data(), bytes_available, &bytes_read))
    {
      output.close();
      std::error_code ec;
      std::filesystem::remove(output_path, ec);
      WinHttpCloseHandle(request);
      WinHttpCloseHandle(connect);
      WinHttpCloseHandle(session);
      out.reason = "artifact_download_read_failed";
      return out;
    }
    output.write(buffer.data(), static_cast<std::streamsize>(bytes_read));
    if (!output.good())
    {
      output.close();
      std::error_code ec;
      std::filesystem::remove(output_path, ec);
      WinHttpCloseHandle(request);
      WinHttpCloseHandle(connect);
      WinHttpCloseHandle(session);
      out.reason = "artifact_download_write_failed";
      return out;
    }
    total_written += static_cast<std::uint64_t>(bytes_read);
  } while (bytes_available > 0);

  output.close();
  WinHttpCloseHandle(request);
  WinHttpCloseHandle(connect);
  WinHttpCloseHandle(session);

  out.ok = true;
  out.size_bytes = total_written;
  return out;
}
#endif

} // namespace

ArtifactUploadTicket ArtifactClient::request_upload(
    const std::string &base_url,
    const std::string &bearer_jwt,
    const std::string &command_id,
    const std::string &content_type,
    std::uint64_t size_bytes,
    std::uint32_t timeout_ms) const
{
  ArtifactUploadTicket ticket{};

  if (command_id.empty())
  {
    ticket.reason = "upload_request_missing_command_id";
    return ticket;
  }

  const std::string root = trim_trailing_slash(base_url);
  if (root.empty())
  {
    ticket.reason = "upload_request_missing_base_url";
    return ticket;
  }

  nlohmann::json payload = {
      {"command_id", command_id},
      {"content_type", content_type.empty() ? "application/octet-stream" : content_type},
      {"size_bytes", size_bytes},
  };

  TelemetryHttpClient http;
  TelemetryHttpResponse response = http.post_json(root + "/api/v1/agent/artifact/request", bearer_jwt, payload.dump(), timeout_ms);
  if (!response.ok && response.status_code == 404)
  {
    // Backward-compat fallback for direct control-plane paths.
    response = http.post_json(root + "/api/artifact/request", bearer_jwt, payload.dump(), timeout_ms);
  }

  if (!response.ok)
  {
    ticket.reason = response.error_reason.empty() ? "upload_request_failed" : response.error_reason;
    return ticket;
  }

  try
  {
    const auto parsed = nlohmann::json::parse(response.body);
    if (parsed.value("status", "") != "ok")
    {
      ticket.reason = "upload_request_rejected";
      return ticket;
    }
    ticket.artifact_id = parsed.value("artifact_id", "");
    ticket.upload_token = parsed.value("upload_token", "");
    ticket.upload_url = parsed.value("upload_url", "");
  }
  catch (const std::exception &)
  {
    ticket.reason = "upload_request_parse_failed";
    return ticket;
  }

  if (ticket.artifact_id.empty() || ticket.upload_token.empty() || ticket.upload_url.empty())
  {
    ticket.reason = "upload_request_missing_fields";
    return ticket;
  }

  ticket.ok = true;
  return ticket;
}

ArtifactUploadResult ArtifactClient::upload_file(
    const std::string &upload_url,
    const std::string &bearer_jwt,
    const std::string &artifact_id,
    const std::string &upload_token,
    const std::string &file_path,
    std::uint32_t timeout_ms) const
{
  ArtifactUploadResult out{};
#ifdef _WIN32
  if (upload_url.empty() || artifact_id.empty() || upload_token.empty() || file_path.empty())
  {
    out.reason = "upload_missing_parameters";
    return out;
  }
  out = upload_multipart_winhttp(upload_url, bearer_jwt, artifact_id, upload_token, file_path, timeout_ms);
  return out;
#else
  (void)upload_url;
  (void)bearer_jwt;
  (void)artifact_id;
  (void)upload_token;
  (void)file_path;
  (void)timeout_ms;
  out.reason = "upload_unsupported_platform";
  return out;
#endif
}

ArtifactDownloadResult ArtifactClient::download_artifact_to_file(
    const std::string &base_url,
    const std::string &bearer_jwt,
    const std::string &artifact_id,
    const std::string &output_path,
    std::uint32_t timeout_ms) const
{
  ArtifactDownloadResult out{};
#ifdef _WIN32
  if (artifact_id.empty() || output_path.empty())
  {
    out.reason = "artifact_download_missing_parameters";
    return out;
  }
  const std::string root = trim_trailing_slash(base_url);
  if (root.empty())
  {
    out.reason = "artifact_download_missing_base_url";
    return out;
  }

  const std::string url = root + "/api/v1/agent/artifact/" + artifact_id;
  out = download_to_file_winhttp(url, bearer_jwt, output_path, timeout_ms);
  return out;
#else
  (void)base_url;
  (void)bearer_jwt;
  (void)artifact_id;
  (void)output_path;
  (void)timeout_ms;
  out.reason = "artifact_download_unsupported_platform";
  return out;
#endif
}

} // namespace command
