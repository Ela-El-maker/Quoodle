// ioctl_signed_request_security_test.cpp
// Verifies that valid Ed25519 signatures are accepted
// and tampered signatures are ALWAYS rejected.

#include <iostream>
#include <string>
#include <vector>
#include <thread>
#include <chrono>
#include <cstdlib>

#ifdef _WIN32
#include <windows.h>

#ifdef HAVE_SODIUM
#include <sodium.h>

static std::string make_pipe_name(const std::string &suffix)
{
  return "\\\\.\\pipe\\KernelServiceTest_" + suffix;
}

static std::string b64_encode(const unsigned char *buf, size_t len)
{
  char out[crypto_sign_BYTES * 2 + 16];
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

void run_mock_kernel(
    const std::string &pipe,
    const std::vector<unsigned char> &pk,
    HANDLE ready_event)
{
  HANDLE hPipe = CreateNamedPipeA(
      pipe.c_str(),
      PIPE_ACCESS_DUPLEX,
      PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT,
      1, 8192, 8192, 0, nullptr);

  if (hPipe == INVALID_HANDLE_VALUE)
    return;

  SetEvent(ready_event);

  if (ConnectNamedPipe(hPipe, nullptr) || GetLastError() == ERROR_PIPE_CONNECTED)
  {
    char buf[8192];
    DWORD read = 0;
    if (ReadFile(hPipe, buf, sizeof(buf), &read, nullptr) && read > 0)
    {
      std::string req(buf, read);

      auto extract = [&](const std::string &k)
      {
        auto p = req.find("\"" + k + "\"");
        if (p == std::string::npos)
          return std::string{};
        auto c = req.find(':', p);
        auto q1 = req.find('"', c);
        auto q2 = req.find('"', q1 + 1);
        return (q1 != std::string::npos && q2 != std::string::npos)
                   ? req.substr(q1 + 1, q2 - q1 - 1)
                   : std::string{};
      };

      std::string payload = extract("signed_payload");
      std::string sig_b64 = extract("sig");

      bool ok = false;
      if (!payload.empty() && !sig_b64.empty())
      {
        std::vector<unsigned char> sig;
        if (b64_decode(sig_b64, sig, crypto_sign_BYTES))
        {
          ok = crypto_sign_verify_detached(
                   sig.data(),
                   reinterpret_cast<const unsigned char *>(payload.data()),
                   payload.size(),
                   pk.data()) == 0;
        }
      }

      std::string resp = ok
                             ? "{\"status\":\"success\",\"error_code\":0}"
                             : "{\"status\":\"error\",\"error_code\":4001,\"error_message\":\"signature_invalid\"}";

      DWORD written = 0;
      WriteFile(hPipe, resp.c_str(), (DWORD)resp.size(), &written, nullptr);
      FlushFileBuffers(hPipe);
    }
  }

  DisconnectNamedPipe(hPipe);
  CloseHandle(hPipe);
}

int main()
{
  const char *sk_b64 = std::getenv("CI_ED25519_SK_B64");
  const char *pk_b64 = std::getenv("CI_ED25519_PUB_B64");

  if (!sk_b64 || !pk_b64)
  {
    std::cout << "ioctl_signed_test: SKIPPED (missing CI keys)\n";
    return 0;
  }

  if (sodium_init() < 0)
    return 2;

  std::vector<unsigned char> sk, pk;
  if (!b64_decode(sk_b64, sk, 64) || !b64_decode(pk_b64, pk, 32))
    return 2;

  const std::string payload = "{\"opcode\":\"lock_screen\",\"request_id\":\"req-1\"}";

  unsigned char sig[crypto_sign_BYTES];
  crypto_sign_detached(sig, nullptr,
                       reinterpret_cast<const unsigned char *>(payload.data()),
                       payload.size(), sk.data());

  // -------- POSITIVE TEST --------
  {
    HANDLE ready = CreateEvent(nullptr, TRUE, FALSE, nullptr);
    std::string pipe = make_pipe_name("pos");

    std::thread server(run_mock_kernel, pipe, pk, ready);
    WaitForSingleObject(ready, 2000);

    HANDLE h = CreateFileA(pipe.c_str(), GENERIC_READ | GENERIC_WRITE,
                           0, nullptr, OPEN_EXISTING, 0, nullptr);

    std::string req =
        "{\"signed_payload\":\"" + payload + "\",\"sig\":\"" +
        b64_encode(sig, crypto_sign_BYTES) + "\"}";

    DWORD written;
    WriteFile(h, req.c_str(), (DWORD)req.size(), &written, nullptr);

    char buf[512]{};
    DWORD read;
    ReadFile(h, buf, sizeof(buf), &read, nullptr);

    CloseHandle(h);
    server.join();

    if (std::string(buf).find("\"error_code\":0") == std::string::npos)
    {
      std::cerr << "FAIL: valid signature rejected\n";
      return 1;
    }
  }

  // -------- NEGATIVE TEST --------
  sig[0] ^= 0xFF;

  {
    HANDLE ready = CreateEvent(nullptr, TRUE, FALSE, nullptr);
    std::string pipe = make_pipe_name("neg");

    std::thread server(run_mock_kernel, pipe, pk, ready);
    WaitForSingleObject(ready, 2000);

    HANDLE h = CreateFileA(pipe.c_str(), GENERIC_READ | GENERIC_WRITE,
                           0, nullptr, OPEN_EXISTING, 0, nullptr);

    std::string req =
        "{\"signed_payload\":\"" + payload + "\",\"sig\":\"" +
        b64_encode(sig, crypto_sign_BYTES) + "\"}";

    DWORD written;
    WriteFile(h, req.c_str(), (DWORD)req.size(), &written, nullptr);

    char buf[512]{};
    DWORD read;
    ReadFile(h, buf, sizeof(buf), &read, nullptr);

    CloseHandle(h);
    server.join();

    if (std::string(buf).find("signature_invalid") == std::string::npos)
    {
      std::cerr << "SECURITY FAILURE: tampered signature accepted\n";
      return 1;
    }
  }

  sodium_memzero(sk.data(), sk.size());
  std::cout << "ioctl_signed_test: ALL PASSED\n";
  return 0;
}
#else
int main()
{
  std::cout << "SKIPPED (libsodium)\n";
  return 0;
}
#endif
#else
int main()
{
  std::cout << "SKIPPED (Windows)\n";
  return 0;
}
#endif
