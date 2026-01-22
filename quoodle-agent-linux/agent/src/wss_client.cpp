#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include "wss_client.h"

#include <arpa/inet.h>
#include <endian.h>
#include <netdb.h>
#include <openssl/err.h>
#include <openssl/ssl.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/statvfs.h>
#include <unistd.h>

#include <sodium.h>

#include <chrono>
#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <random>
#include <sstream>

#include <nlohmann/json.hpp>

#include "crypto.h"

namespace quoodle {
namespace {

struct WsUrl {
    std::string host;
    std::string path;
    int port{80};
    bool tls{false};
};

std::string GetEnvOrDefault(const char *name, const char *fallback) {
    const char *value = std::getenv(name);
    if (value && *value) {
        return value;
    }
    return fallback;
}

bool ParseWsUrl(const std::string &url, WsUrl *out) {
    const std::string ws_prefix = "ws://";
    const std::string wss_prefix = "wss://";
    std::string rest;
    if (url.rfind(ws_prefix, 0) == 0) {
        rest = url.substr(ws_prefix.size());
        out->tls = false;
    } else if (url.rfind(wss_prefix, 0) == 0) {
        rest = url.substr(wss_prefix.size());
        out->tls = true;
        out->port = 443;
    } else {
        return false;
    }
    auto slash = rest.find('/');
    std::string hostport = (slash == std::string::npos) ? rest : rest.substr(0, slash);
    out->path = (slash == std::string::npos) ? "/" : rest.substr(slash);
    auto colon = hostport.find(':');
    if (colon != std::string::npos) {
        out->host = hostport.substr(0, colon);
        out->port = std::stoi(hostport.substr(colon + 1));
    } else {
        out->host = hostport;
        if (!out->tls) {
            out->port = 80;
        }
    }
    return !out->host.empty();
}

int ConnectTcp(const WsUrl &url) {
    addrinfo hints{};
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    addrinfo *res = nullptr;
    std::string port = std::to_string(url.port);
    if (getaddrinfo(url.host.c_str(), port.c_str(), &hints, &res) != 0) {
        return -1;
    }
    int fd = -1;
    for (addrinfo *p = res; p; p = p->ai_next) {
        fd = socket(p->ai_family, p->ai_socktype, p->ai_protocol);
        if (fd < 0) {
            continue;
        }
        if (connect(fd, p->ai_addr, p->ai_addrlen) == 0) {
            break;
        }
        close(fd);
        fd = -1;
    }
    freeaddrinfo(res);
    return fd;
}

struct IoState {
    int fd{-1};
    SSL *ssl{nullptr};
    bool tls{false};
};

ssize_t IoRead(IoState *io, void *buf, size_t len) {
    if (!io || io->fd < 0) {
        return -1;
    }
    if (!io->tls) {
        return read(io->fd, buf, len);
    }
    while (true) {
        int r = SSL_read(io->ssl, buf, static_cast<int>(len));
        if (r > 0) {
            return r;
        }
        int err = SSL_get_error(io->ssl, r);
        if (err == SSL_ERROR_WANT_READ || err == SSL_ERROR_WANT_WRITE) {
            continue;
        }
        return -1;
    }
}

ssize_t IoWrite(IoState *io, const void *buf, size_t len) {
    if (!io || io->fd < 0) {
        return -1;
    }
    if (!io->tls) {
        return write(io->fd, buf, len);
    }
    while (true) {
        int w = SSL_write(io->ssl, buf, static_cast<int>(len));
        if (w > 0) {
            return w;
        }
        int err = SSL_get_error(io->ssl, w);
        if (err == SSL_ERROR_WANT_READ || err == SSL_ERROR_WANT_WRITE) {
            continue;
        }
        return -1;
    }
}

bool ReadExact(IoState *io, void *buf, size_t len) {
    size_t off = 0;
    while (off < len) {
        ssize_t r = IoRead(io, static_cast<char *>(buf) + off, len - off);
        if (r <= 0) {
            return false;
        }
        off += static_cast<size_t>(r);
    }
    return true;
}

bool WriteExact(IoState *io, const void *buf, size_t len) {
    size_t off = 0;
    while (off < len) {
        ssize_t w = IoWrite(io, static_cast<const char *>(buf) + off, len - off);
        if (w <= 0) {
            return false;
        }
        off += static_cast<size_t>(w);
    }
    return true;
}

std::string Base64Encode(const unsigned char *data, size_t len) {
    size_t out_len = sodium_base64_ENCODED_LEN(len, sodium_base64_VARIANT_ORIGINAL);
    std::string out(out_len, '\0');
    sodium_bin2base64(out.data(), out_len, data, len, sodium_base64_VARIANT_ORIGINAL);
    if (!out.empty() && out.back() == '\0') {
        out.pop_back();
    }
    return out;
}

std::string GenerateWsKey() {
    unsigned char buf[16];
    randombytes_buf(buf, sizeof(buf));
    return Base64Encode(buf, sizeof(buf));
}

std::string Sha1DigestHex(const std::string &data) {
    uint32_t h0 = 0x67452301;
    uint32_t h1 = 0xefcdab89;
    uint32_t h2 = 0x98badcfe;
    uint32_t h3 = 0x10325476;
    uint32_t h4 = 0xc3d2e1f0;

    std::string msg = data;
    uint64_t bits = msg.size() * 8ULL;
    msg.push_back(static_cast<char>(0x80));
    while ((msg.size() % 64) != 56) {
        msg.push_back(static_cast<char>(0x00));
    }
    for (int i = 7; i >= 0; --i) {
        msg.push_back(static_cast<char>((bits >> (i * 8)) & 0xFF));
    }

    for (size_t chunk = 0; chunk < msg.size(); chunk += 64) {
        uint32_t w[80];
        for (int i = 0; i < 16; ++i) {
            size_t offset = chunk + i * 4;
            w[i] = (static_cast<uint8_t>(msg[offset]) << 24) |
                   (static_cast<uint8_t>(msg[offset + 1]) << 16) |
                   (static_cast<uint8_t>(msg[offset + 2]) << 8) |
                   (static_cast<uint8_t>(msg[offset + 3]));
        }
        for (int i = 16; i < 80; ++i) {
            uint32_t val = w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16];
            w[i] = (val << 1) | (val >> 31);
        }

        uint32_t a = h0;
        uint32_t b = h1;
        uint32_t c = h2;
        uint32_t d = h3;
        uint32_t e = h4;

        for (int i = 0; i < 80; ++i) {
            uint32_t f = 0;
            uint32_t k = 0;
            if (i < 20) {
                f = (b & c) | ((~b) & d);
                k = 0x5a827999;
            } else if (i < 40) {
                f = b ^ c ^ d;
                k = 0x6ed9eba1;
            } else if (i < 60) {
                f = (b & c) | (b & d) | (c & d);
                k = 0x8f1bbcdc;
            } else {
                f = b ^ c ^ d;
                k = 0xca62c1d6;
            }
            uint32_t temp = ((a << 5) | (a >> 27)) + f + e + k + w[i];
            e = d;
            d = c;
            c = (b << 30) | (b >> 2);
            b = a;
            a = temp;
        }

        h0 += a;
        h1 += b;
        h2 += c;
        h3 += d;
        h4 += e;
    }

    unsigned char digest[20];
    uint32_t h[5] = {h0, h1, h2, h3, h4};
    for (int i = 0; i < 5; ++i) {
        digest[i * 4] = static_cast<unsigned char>((h[i] >> 24) & 0xFF);
        digest[i * 4 + 1] = static_cast<unsigned char>((h[i] >> 16) & 0xFF);
        digest[i * 4 + 2] = static_cast<unsigned char>((h[i] >> 8) & 0xFF);
        digest[i * 4 + 3] = static_cast<unsigned char>((h[i]) & 0xFF);
    }
    return std::string(reinterpret_cast<char *>(digest), sizeof(digest));
}

std::string ComputeAcceptKey(const std::string &client_key) {
    static const std::string kGuid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    std::string sha1 = Sha1DigestHex(client_key + kGuid);
    return Base64Encode(reinterpret_cast<const unsigned char *>(sha1.data()), sha1.size());
}

bool ReadHttpResponse(IoState *io, std::string *response) {
    std::string buf;
    char tmp[512];
    while (buf.find("\r\n\r\n") == std::string::npos) {
        ssize_t r = IoRead(io, tmp, sizeof(tmp));
        if (r <= 0) {
            return false;
        }
        buf.append(tmp, static_cast<size_t>(r));
        if (buf.size() > 8192) {
            return false;
        }
    }
    *response = buf;
    return true;
}

std::string Lower(const std::string &s) {
    std::string out = s;
    for (auto &ch : out) {
        ch = static_cast<char>(std::tolower(ch));
    }
    return out;
}

bool ValidateHandshake(const std::string &response, const std::string &accept_key) {
    if (response.find("101") == std::string::npos) {
        return false;
    }
    std::string lower = Lower(response);
    std::string needle = "sec-websocket-accept:";
    auto pos = lower.find(needle);
    if (pos == std::string::npos) {
        return false;
    }
    auto line_end = lower.find("\r\n", pos);
    std::string line = response.substr(pos, line_end - pos);
    auto colon = line.find(':');
    if (colon == std::string::npos) {
        return false;
    }
    std::string value = line.substr(colon + 1);
    while (!value.empty() && std::isspace(value.front())) {
        value.erase(value.begin());
    }
    return value == accept_key;
}

bool SendWsFrame(IoState *io, const std::string &payload, uint8_t opcode) {
    uint8_t header[14];
    size_t header_len = 0;
    header[0] = 0x80 | (opcode & 0x0F);

    uint8_t mask_key[4];
    randombytes_buf(mask_key, sizeof(mask_key));

    size_t payload_len = payload.size();
    if (payload_len <= 125) {
        header[1] = 0x80 | static_cast<uint8_t>(payload_len);
        header_len = 2;
    } else if (payload_len <= 0xFFFF) {
        header[1] = 0x80 | 126;
        uint16_t len = htons(static_cast<uint16_t>(payload_len));
        std::memcpy(&header[2], &len, sizeof(len));
        header_len = 4;
    } else {
        header[1] = 0x80 | 127;
        uint64_t len = htobe64(static_cast<uint64_t>(payload_len));
        std::memcpy(&header[2], &len, sizeof(len));
        header_len = 10;
    }
    std::memcpy(&header[header_len], mask_key, sizeof(mask_key));
    header_len += sizeof(mask_key);

    std::string masked = payload;
    for (size_t i = 0; i < payload.size(); ++i) {
        masked[i] = static_cast<char>(payload[i] ^ mask_key[i % 4]);
    }

    if (!WriteExact(io, header, header_len)) {
        return false;
    }
    return WriteExact(io, masked.data(), masked.size());
}

bool ReadWsFrame(IoState *io, std::string *payload, uint8_t *opcode) {
    uint8_t header[2];
    if (!ReadExact(io, header, sizeof(header))) {
        return false;
    }
    bool fin = header[0] & 0x80;
    uint8_t op = header[0] & 0x0F;
    bool masked = header[1] & 0x80;
    uint64_t len = header[1] & 0x7F;
    if (!fin) {
        return false;
    }
    if (len == 126) {
        uint16_t ext = 0;
        if (!ReadExact(io, &ext, sizeof(ext))) {
            return false;
        }
        len = ntohs(ext);
    } else if (len == 127) {
        uint64_t ext = 0;
        if (!ReadExact(io, &ext, sizeof(ext))) {
            return false;
        }
        len = be64toh(ext);
    }
    uint8_t mask_key[4] = {0};
    if (masked) {
        if (!ReadExact(io, mask_key, sizeof(mask_key))) {
            return false;
        }
    }
    if (len > 1024 * 1024) {
        return false;
    }
    std::string data(len, '\0');
    if (!ReadExact(io, data.data(), len)) {
        return false;
    }
    if (masked) {
        for (size_t i = 0; i < data.size(); ++i) {
            data[i] = static_cast<char>(data[i] ^ mask_key[i % 4]);
        }
    }
    *payload = std::move(data);
    *opcode = op;
    return true;
}

std::string BuildIsoTimestamp() {
    auto now = std::chrono::system_clock::now();
    std::time_t tt = std::chrono::system_clock::to_time_t(now);
    std::tm tm{};
    gmtime_r(&tt, &tm);
    char buf[32];
    std::strftime(buf, sizeof(buf), "%Y-%m-%dT%H:%M:%SZ", &tm);
    return buf;
}

bool ParseIsoTimestamp(const std::string &ts, std::time_t *out) {
    std::string cleaned = ts;
    auto dot = cleaned.find('.');
    if (dot != std::string::npos) {
        auto zpos = cleaned.find('Z', dot);
        if (zpos != std::string::npos) {
            cleaned.erase(dot, zpos - dot);
        }
    }
    std::tm tm{};
    char *res = strptime(cleaned.c_str(), "%Y-%m-%dT%H:%M:%SZ", &tm);
    if (!res || *res != '\0') {
        return false;
    }
    *out = timegm(&tm);
    return true;
}

bool IsTimestampFresh(const std::string &ts) {
    std::time_t parsed = 0;
    if (!ParseIsoTimestamp(ts, &parsed)) {
        return false;
    }
    long skew = std::strtol(GetEnvOrDefault("QUOODLE_MAX_CLOCK_SKEW", "120").c_str(), nullptr, 10);
    std::time_t now = std::time(nullptr);
    long diff = static_cast<long>(std::labs(now - parsed));
    return diff <= skew;
}

std::string GenerateMessageId() {
    std::ifstream in("/proc/sys/kernel/random/uuid");
    if (in.good()) {
        std::string uuid;
        std::getline(in, uuid);
        if (!uuid.empty()) {
            return uuid;
        }
    }
    std::random_device rd;
    std::uniform_int_distribution<int> dist(0, 15);
    std::string hex = "0123456789abcdef";
    std::string uuid;
    uuid.reserve(36);
    for (int i = 0; i < 36; ++i) {
        if (i == 8 || i == 13 || i == 18 || i == 23) {
            uuid.push_back('-');
        } else {
            uuid.push_back(hex[dist(rd)]);
        }
    }
    return uuid;
}

void StripSigRecursive(nlohmann::json &value) {
    if (value.is_object()) {
        value.erase("sig");
        for (auto &item : value.items()) {
            StripSigRecursive(item.value());
        }
    } else if (value.is_array()) {
        for (auto &item : value) {
            StripSigRecursive(item);
        }
    }
}

std::string CanonicalizeWss(const nlohmann::json &payload) {
    nlohmann::json copy = payload;
    StripSigRecursive(copy);
    return copy.dump();
}

std::string FormatPercent(int value) {
    if (value < 0) value = 0;
    if (value > 100) value = 100;
    return std::to_string(value) + "%";
}

std::string FormatMbps(double value) {
    std::ostringstream oss;
    oss << std::fixed << std::setprecision(1) << value << "Mbps";
    return oss.str();
}

bool ReadCpuCounters(uint64_t *total, uint64_t *idle) {
    std::ifstream in("/proc/stat");
    if (!in.good()) {
        return false;
    }
    std::string cpu;
    uint64_t user = 0, nice = 0, system = 0, idle_v = 0, iowait = 0, irq = 0, softirq = 0, steal = 0;
    in >> cpu >> user >> nice >> system >> idle_v >> iowait >> irq >> softirq >> steal;
    if (cpu != "cpu") {
        return false;
    }
    *idle = idle_v + iowait;
    *total = user + nice + system + *idle + irq + softirq + steal;
    return true;
}

bool ReadMemUsage(int *percent) {
    std::ifstream in("/proc/meminfo");
    if (!in.good()) {
        return false;
    }
    std::string key;
    uint64_t value = 0;
    std::string unit;
    uint64_t total = 0;
    uint64_t available = 0;
    while (in >> key >> value >> unit) {
        if (key == "MemTotal:") {
            total = value;
        } else if (key == "MemAvailable:") {
            available = value;
        }
        if (total && available) {
            break;
        }
    }
    if (!total) {
        return false;
    }
    uint64_t used = (available > total) ? 0 : (total - available);
    *percent = static_cast<int>((used * 100) / total);
    return true;
}

bool ReadDiskUsage(int *percent) {
    struct statvfs stats;
    if (statvfs("/", &stats) != 0) {
        return false;
    }
    uint64_t total = static_cast<uint64_t>(stats.f_blocks) * stats.f_frsize;
    uint64_t free = static_cast<uint64_t>(stats.f_bfree) * stats.f_frsize;
    if (!total) {
        return false;
    }
    uint64_t used = total > free ? (total - free) : 0;
    *percent = static_cast<int>((used * 100) / total);
    return true;
}

bool ReadNetCounters(uint64_t *tx_bytes, uint64_t *rx_bytes) {
    std::ifstream in("/proc/net/dev");
    if (!in.good()) {
        return false;
    }
    std::string line;
    std::getline(in, line);
    std::getline(in, line);
    uint64_t tx_sum = 0;
    uint64_t rx_sum = 0;
    while (std::getline(in, line)) {
        auto colon = line.find(':');
        if (colon == std::string::npos) {
            continue;
        }
        std::string iface = line.substr(0, colon);
        iface.erase(0, iface.find_first_not_of(" \t"));
        iface.erase(iface.find_last_not_of(" \t") + 1);
        if (iface == "lo") {
            continue;
        }
        std::istringstream iss(line.substr(colon + 1));
        uint64_t rx = 0;
        uint64_t tx = 0;
        uint64_t tmp = 0;
        if (!(iss >> rx)) {
            continue;
        }
        for (int i = 0; i < 7; ++i) {
            iss >> tmp;
        }
        if (!(iss >> tx)) {
            continue;
        }
        rx_sum += rx;
        tx_sum += tx;
    }
    *tx_bytes = tx_sum;
    *rx_bytes = rx_sum;
    return true;
}

std::string GetStringOrDefault(const nlohmann::json &obj, const char *key, const std::string &fallback) {
    if (obj.contains(key) && obj[key].is_string()) {
        return obj[key].get<std::string>();
    }
    return fallback;
}

int GetIntOrDefault(const nlohmann::json &obj, const char *key, int fallback) {
    if (obj.contains(key) && obj[key].is_number_integer()) {
        return obj[key].get<int>();
    }
    return fallback;
}

bool GetBoolOrDefault(const nlohmann::json &obj, const char *key, bool fallback) {
    if (obj.contains(key) && obj[key].is_boolean()) {
        return obj[key].get<bool>();
    }
    return fallback;
}

nlohmann::json GetObjectOrEmpty(const nlohmann::json &obj, const char *key) {
    if (obj.contains(key) && obj[key].is_object()) {
        return obj[key];
    }
    return nlohmann::json::object();
}

}  // namespace

WssClient::WssClient(std::string ws_url,
                     std::string device_id,
                     std::string agent_jwt,
                     std::string agent_kid,
                     std::string agent_priv_b64,
                     PolicyState &policy,
                     Outbox &outbox,
                     ReplayCache &replay,
                     AgentStateStore &state,
                     CommandProcessor &processor)
    : ws_url_(std::move(ws_url)),
      device_id_(std::move(device_id)),
      agent_jwt_(std::move(agent_jwt)),
      agent_kid_(std::move(agent_kid)),
      agent_priv_b64_(std::move(agent_priv_b64)),
      policy_(policy),
      outbox_(outbox),
      replay_(replay),
      state_(state),
      processor_(processor) {}

bool WssClient::SendSigned(const nlohmann::json &payload) {
    nlohmann::json msg = payload;
    std::string canonical;
    try {
        canonical = CanonicalizeWss(msg);
    } catch (const std::exception &ex) {
        std::cerr << "CanonicalizeWss failed: " << ex.what() << "\n";
        return false;
    }
    std::string sig;
    try {
        sig = SignEd25519(agent_priv_b64_, canonical);
    } catch (const std::exception &ex) {
        std::cerr << "Signing failed: " << ex.what() << "\n";
        return false;
    }
    msg["sig"] = sig;
    IoState io{socket_fd_, tls_, use_tls_};
    std::string outbound;
    try {
        outbound = msg.dump();
    } catch (const std::exception &ex) {
        std::cerr << "Message dump failed: " << ex.what() << "\n";
        return false;
    }
    return SendWsFrame(&io, outbound, 0x1);
}

bool WssClient::SendAuth() {
    nlohmann::json body;
    body["auth"] = {{"jwt", agent_jwt_}, {"nonce", GenerateMessageId()}};
    auto agent_info = policy_.AgentInfo();
    body["agent_info"] = {
        {"agent_version", agent_info["agent_version"]},
        {"os_build", agent_info["os_build"]},
        {"hwid_hash", policy_.HwidHash()},
    };
    std::string attestation = GetEnvOrDefault("QUOODLE_ATTESTATION_HASH", "");
    if (!attestation.empty()) {
        body["agent_info"]["attestation_hash"] = attestation;
    }

    nlohmann::json msg;
    msg["message_id"] = GenerateMessageId();
    msg["timestamp"] = BuildIsoTimestamp();
    msg["type"] = "AUTH";
    msg["from"] = "agent";
    msg["device_id"] = device_id_;
    msg["session_id"] = nullptr;
    msg["seq"] = replay_.NextSeq();
    msg["body"] = body;
    msg["sig"] = "";
    return SendSigned(msg);
}

bool WssClient::VerifyControllerSig(const nlohmann::json &msg) const {
    std::string pub = GetEnvOrDefault("QUOODLE_CONTROLLER_PUBKEY_B64", "");
    if (pub.empty()) {
        bool allow = GetEnvOrDefault("QUOODLE_ALLOW_UNVERIFIED_WSS", "false") == "true";
        if (!allow) {
            return false;
        }
        return true;
    }
    if (!msg.contains("sig") || !msg["sig"].is_string()) {
        return false;
    }
    std::string sig = msg["sig"].get<std::string>();
    std::string canonical = CanonicalizeWss(msg);
    return VerifyEd25519(pub, canonical, sig);
}

bool WssClient::VerifyEnvelopeSig(const nlohmann::json &env) const {
    std::string pub = GetEnvOrDefault("QUOODLE_CONTROLLER_PUBKEY_B64", "");
    if (pub.empty()) {
        bool allow = GetEnvOrDefault("QUOODLE_ALLOW_UNVERIFIED_WSS", "false") == "true";
        if (!allow) {
            return false;
        }
        return true;
    }
    if (!env.contains("sig") || !env["sig"].is_string()) {
        return false;
    }
    std::string sig = env["sig"].get<std::string>();
    std::string canonical = CanonicalizeWss(env);
    return VerifyEd25519(pub, canonical, sig);
}

bool WssClient::HandleAuthAck(const nlohmann::json &msg) {
    auto body = GetObjectOrEmpty(msg, "body");
    session_id_ = GetStringOrDefault(body, "session_id", "");
    heartbeat_interval_ = GetIntOrDefault(body, "heartbeat_interval_seconds", heartbeat_interval_);
    telemetry_interval_ = GetIntOrDefault(body, "telemetry_interval_seconds", telemetry_interval_);
    std::string policy_hash = GetStringOrDefault(body, "policy_hash", "");
    if (!policy_hash.empty()) {
        policy_.SetPolicyHash(policy_hash);
        state_.SetPolicyHash(policy_hash);
    }
    authenticated_ = true;
    return true;
}

bool WssClient::HandlePolicyUpdate(const nlohmann::json &msg) {
    auto body = GetObjectOrEmpty(msg, "body");
    std::string policy_hash = GetStringOrDefault(body, "policy_hash", "");
    if (!policy_hash.empty()) {
        policy_.SetPolicyHash(policy_hash);
        state_.SetPolicyHash(policy_hash);
    }
    return true;
}

bool WssClient::HandleCommandDelivery(const nlohmann::json &msg) {
    auto body = GetObjectOrEmpty(msg, "body");
    auto env = GetObjectOrEmpty(body, "command_envelope");
    if (env.empty()) {
        return false;
    }
    if (!VerifyEnvelopeSig(env)) {
        std::cerr << "Invalid command envelope signature\n";
        if (GetEnvOrDefault("QUOODLE_DEBUG_SIG", "false") == "true") {
            std::cerr << "Envelope: " << env.dump() << "\n";
            std::cerr << "Envelope canonical: " << CanonicalizeWss(env) << "\n";
            if (env.contains("sig")) {
                std::cerr << "Envelope sig: " << env["sig"].dump() << "\n";
            }
        }
        return false;
    }

    std::string delivery_id = GetStringOrDefault(msg, "message_id", "");
    if (!delivery_id.empty() && delivery_id == state_.LastDeliveryId()) {
        return true;
    }

    auto header = GetObjectOrEmpty(env, "header");
    auto env_body = GetObjectOrEmpty(env, "body");
    auto meta = GetObjectOrEmpty(env, "meta");

    std::string command_id = GetStringOrDefault(env, "message_id", "");
    std::string method = GetStringOrDefault(env_body, "method", "");
    nlohmann::json params = GetObjectOrEmpty(env_body, "params");
    bool requires_ack = GetBoolOrDefault(header, "requires_ack", true);
    std::string policy_hash = GetStringOrDefault(meta, "policy_hash", policy_.PolicyHash());

    std::string ts = GetStringOrDefault(header, "timestamp", "");
    int ttl = GetIntOrDefault(header, "ttl_seconds", 0);
    bool expired = false;
    if (!ts.empty() && ttl > 0) {
        std::time_t base = 0;
        if (ParseIsoTimestamp(ts, &base)) {
            expired = std::time(nullptr) > (base + ttl);
        }
    }
    if (expired) {
        if (!delivery_id.empty()) {
            state_.SetLastDeliveryId(delivery_id);
        }
        outbox_.EnqueueAck(command_id, device_id_, "rejected", "expired_ttl");
        ExecutionResult result;
        result.execution_state = "failed";
        result.status = "error";
        result.error_type = "ERR_EXECUTION_FAILED";
        result.error_message = "expired_ttl";
        result.result = nlohmann::json::object();
        outbox_.EnqueueResult(command_id, device_id_, result);
        return true;
    }

    CommandEnvelope cmd;
    cmd.command_id = command_id;
    cmd.method = method;
    cmd.params = params;
    cmd.requires_ack = requires_ack;
    cmd.device_id = device_id_;
    cmd.delivery_id = delivery_id;
    cmd.policy_hash = policy_hash;

    processor_.Handle(cmd);
    return true;
}

bool WssClient::HandleUpdateAnnounce(const nlohmann::json &msg) {
    auto body = GetObjectOrEmpty(msg, "body");
    std::string release_id = GetStringOrDefault(body, "release_id", "");
    std::string version = GetStringOrDefault(body, "version", "");

    nlohmann::json status_body;
    status_body["release_id"] = release_id;
    status_body["version"] = version;
    status_body["phase"] = "failed";
    status_body["progress"] = {
        {"percent", 0},
        {"detail", "update_not_supported"}
    };
    status_body["error_code"] = 1001;
    status_body["error_message"] = "update_not_supported";
    status_body["rollback_snapshot_id"] = nullptr;

    nlohmann::json msg_out;
    msg_out["message_id"] = GenerateMessageId();
    msg_out["timestamp"] = BuildIsoTimestamp();
    msg_out["type"] = "UPDATE_STATUS";
    msg_out["from"] = "agent";
    msg_out["device_id"] = device_id_;
    msg_out["session_id"] = session_id_;
    msg_out["seq"] = replay_.NextSeq();
    msg_out["body"] = status_body;
    msg_out["sig"] = "";
    return SendSigned(msg_out);
}

bool WssClient::FlushOutbox() {
    while (true) {
        const OutboxItem *item = outbox_.Peek();
        if (!item) {
            return true;
        }
        nlohmann::json body;
        std::string type;
        try {
            if (item->type == "COMMAND_ACK") {
                type = "COMMAND_ACK";
                body["command_message_id"] = item->command_id;
                body["status"] = item->ack_status.empty() ? "received" : item->ack_status;
                if (!item->ack_reason.empty()) {
                    body["reason"] = item->ack_reason;
                } else {
                    body["reason"] = nullptr;
                }
            } else if (item->type == "COMMAND_RESULT") {
                type = "COMMAND_RESULT";
                body["command_message_id"] = item->command_id;
                body["execution_state"] =
                    item->result.execution_state.empty() ? "completed" : item->result.execution_state;
                nlohmann::json result;
                std::string status = item->result.status.empty()
                                         ? (body["execution_state"] == "completed" ? "ok" : "error")
                                         : item->result.status;
                result["status"] = status;
                if (!item->result.error_message.empty()) {
                    result["notes"] = item->result.error_message;
                }
                if (!item->result.result.is_null() && !item->result.result.empty()) {
                    result["details"] = item->result.result;
                }
                body["result"] = result;
                body["error_code"] = nullptr;
                if (item->result.error_message.empty()) {
                    body["error_message"] = nullptr;
                } else {
                    body["error_message"] = item->result.error_message;
                }
            } else {
                outbox_.PopFront();
                continue;
            }
        } catch (const std::exception &ex) {
            std::cerr << "FlushOutbox build failed: " << ex.what() << "\n";
            return false;
        }

        nlohmann::json msg;
        msg["message_id"] = GenerateMessageId();
        msg["timestamp"] = BuildIsoTimestamp();
        msg["type"] = type;
        msg["from"] = "agent";
        msg["device_id"] = device_id_;
        msg["session_id"] = session_id_;
        msg["seq"] = replay_.NextSeq();
        msg["body"] = body;
        msg["sig"] = "";

        if (!SendSigned(msg)) {
            return false;
        }
        outbox_.PopFront();
    }
}

bool WssClient::SendHeartbeat() {
    if (!authenticated_) {
        return true;
    }
    nlohmann::json body;
    body["status"] = "alive";
    body["uptime_seconds"] = static_cast<int>(std::time(nullptr) - start_time_);
    body["error_state"] = "ok";
    body["policy_hash"] = policy_.PolicyHash();

    nlohmann::json msg;
    msg["message_id"] = GenerateMessageId();
    msg["timestamp"] = BuildIsoTimestamp();
    msg["type"] = "HEARTBEAT";
    msg["from"] = "agent";
    msg["device_id"] = device_id_;
    msg["session_id"] = session_id_;
    msg["seq"] = replay_.NextSeq();
    msg["body"] = body;
    msg["sig"] = "";
    return SendSigned(msg);
}

bool WssClient::SendTelemetry() {
    if (!authenticated_) {
        return true;
    }
    int cpu_pct = 0;
    int mem_pct = 0;
    int disk_pct = 0;
    uint64_t total = 0;
    uint64_t idle = 0;
    if (ReadCpuCounters(&total, &idle)) {
        if (has_cpu_sample_) {
            uint64_t total_delta = total - last_cpu_total_;
            uint64_t idle_delta = idle - last_cpu_idle_;
            if (total_delta > 0 && total_delta >= idle_delta) {
                cpu_pct = static_cast<int>(((total_delta - idle_delta) * 100) / total_delta);
            }
        }
        last_cpu_total_ = total;
        last_cpu_idle_ = idle;
        has_cpu_sample_ = true;
    }
    if (!ReadMemUsage(&mem_pct)) {
        mem_pct = 0;
    }
    if (!ReadDiskUsage(&disk_pct)) {
        disk_pct = 0;
    }

    uint64_t tx = 0;
    uint64_t rx = 0;
    double tx_mbps = 0.0;
    double rx_mbps = 0.0;
    if (ReadNetCounters(&tx, &rx)) {
        if (has_net_sample_ && last_telemetry_ > 0) {
            double delta = std::max(1.0, difftime(std::time(nullptr), last_telemetry_));
            tx_mbps = ((tx - last_net_tx_) * 8.0) / (delta * 1e6);
            rx_mbps = ((rx - last_net_rx_) * 8.0) / (delta * 1e6);
        }
        last_net_tx_ = tx;
        last_net_rx_ = rx;
        has_net_sample_ = true;
    }

    nlohmann::json metrics;
    metrics["cpu"] = FormatPercent(cpu_pct);
    metrics["ram"] = FormatPercent(mem_pct);
    metrics["disk_usage"] = FormatPercent(disk_pct);
    metrics["network_tx"] = FormatMbps(tx_mbps);
    metrics["network_rx"] = FormatMbps(rx_mbps);

    nlohmann::json body;
    body["timestamp"] = BuildIsoTimestamp();
    body["metrics"] = metrics;
    body["telemetry_scope"] = "telemetry_basic";

    nlohmann::json msg;
    msg["message_id"] = GenerateMessageId();
    msg["timestamp"] = BuildIsoTimestamp();
    msg["type"] = "TELEMETRY";
    msg["from"] = "agent";
    msg["device_id"] = device_id_;
    msg["session_id"] = session_id_;
    msg["seq"] = replay_.NextSeq();
    msg["body"] = body;
    msg["sig"] = "";
    return SendSigned(msg);
}

bool WssClient::ProcessInbound(const std::string &payload) {
    nlohmann::json msg;
    try {
        msg = nlohmann::json::parse(payload);
    } catch (const std::exception &ex) {
        std::cerr << "Invalid JSON from gateway: " << ex.what() << "\n";
        return false;
    }
    if (!msg.is_object()) {
        return false;
    }
    try {
        if (!VerifyControllerSig(msg)) {
            std::cerr << "Controller signature invalid\n";
            return false;
        }
    } catch (const std::exception &ex) {
        std::cerr << "VerifyControllerSig failed: " << ex.what() << "\n";
        throw;
    }
    std::string type = GetStringOrDefault(msg, "type", "");
    if (type.empty()) {
        return false;
    }
    if (msg.contains("device_id") && msg["device_id"].is_string()) {
        std::string target = msg["device_id"].get<std::string>();
        if (!target.empty() && target != device_id_) {
            return true;
        }
    }
    if (msg.contains("timestamp") && msg["timestamp"].is_string()) {
        if (!IsTimestampFresh(msg["timestamp"].get<std::string>())) {
            std::cerr << "Stale timestamp from controller\n";
            return false;
        }
    }
    if (msg.contains("seq") && msg["seq"].is_number_integer()) {
        long seq = msg["seq"].get<long>();
        if (seq <= last_controller_seq_) {
            return true;
        }
        last_controller_seq_ = seq;
    }

    if (type == "AUTH_ACK") {
        try {
            return HandleAuthAck(msg);
        } catch (const std::exception &ex) {
            std::cerr << "HandleAuthAck failed: " << ex.what() << "\n";
            throw;
        }
    }
    if (type == "AUTH_ERROR") {
        std::cerr << "AUTH_ERROR from gateway\n";
        return false;
    }
    if (!authenticated_) {
        return false;
    }
    if (type == "COMMAND_DELIVERY") {
        try {
            return HandleCommandDelivery(msg);
        } catch (const std::exception &ex) {
            std::cerr << "HandleCommandDelivery failed: " << ex.what() << "\n";
            throw;
        }
    }
    if (type == "POLICY_UPDATE") {
        try {
            return HandlePolicyUpdate(msg);
        } catch (const std::exception &ex) {
            std::cerr << "HandlePolicyUpdate failed: " << ex.what() << "\n";
            throw;
        }
    }
    if (type == "UPDATE_ANNOUNCE") {
        try {
            return HandleUpdateAnnounce(msg);
        } catch (const std::exception &ex) {
            std::cerr << "HandleUpdateAnnounce failed: " << ex.what() << "\n";
            throw;
        }
    }
    return true;
}

bool WssClient::InitTls(const std::string &host) {
    use_tls_ = true;
    SSL_load_error_strings();
    OpenSSL_add_ssl_algorithms();

    tls_ctx_ = SSL_CTX_new(TLS_client_method());
    if (!tls_ctx_) {
        std::cerr << "TLS: failed to create context\n";
        use_tls_ = false;
        return false;
    }
    bool insecure = GetEnvOrDefault("QUOODLE_TLS_INSECURE", "false") == "true";
    if (insecure) {
        SSL_CTX_set_verify(tls_ctx_, SSL_VERIFY_NONE, nullptr);
    } else {
        SSL_CTX_set_verify(tls_ctx_, SSL_VERIFY_PEER, nullptr);
        SSL_CTX_set_default_verify_paths(tls_ctx_);
        std::string cafile = GetEnvOrDefault("QUOODLE_TLS_CA_FILE", "");
        std::string capath = GetEnvOrDefault("QUOODLE_TLS_CA_PATH", "");
        if (!cafile.empty() || !capath.empty()) {
            if (SSL_CTX_load_verify_locations(tls_ctx_,
                                              cafile.empty() ? nullptr : cafile.c_str(),
                                              capath.empty() ? nullptr : capath.c_str()) != 1) {
                std::cerr << "TLS: failed to load CA locations\n";
                SSL_CTX_free(tls_ctx_);
                tls_ctx_ = nullptr;
                use_tls_ = false;
                return false;
            }
        }
    }

    tls_ = SSL_new(tls_ctx_);
    if (!tls_) {
        std::cerr << "TLS: failed to allocate session\n";
        SSL_CTX_free(tls_ctx_);
        tls_ctx_ = nullptr;
        use_tls_ = false;
        return false;
    }
    SSL_set_fd(tls_, socket_fd_);
    SSL_set_tlsext_host_name(tls_, host.c_str());

    if (SSL_connect(tls_) <= 0) {
        std::cerr << "TLS: handshake failed\n";
        SSL_free(tls_);
        tls_ = nullptr;
        SSL_CTX_free(tls_ctx_);
        tls_ctx_ = nullptr;
        use_tls_ = false;
        return false;
    }
    if (!insecure) {
        long verify = SSL_get_verify_result(tls_);
        if (verify != X509_V_OK) {
            std::cerr << "TLS: certificate verify failed\n";
            SSL_free(tls_);
            tls_ = nullptr;
            SSL_CTX_free(tls_ctx_);
            tls_ctx_ = nullptr;
            use_tls_ = false;
            return false;
        }
    }
    return true;
}

void WssClient::CloseTransport() {
    if (tls_) {
        SSL_shutdown(tls_);
        SSL_free(tls_);
        tls_ = nullptr;
    }
    if (tls_ctx_) {
        SSL_CTX_free(tls_ctx_);
        tls_ctx_ = nullptr;
    }
    if (socket_fd_ >= 0) {
        close(socket_fd_);
        socket_fd_ = -1;
    }
    use_tls_ = false;
}

void WssClient::Run() {
    if (sodium_init() < 0) {
        std::cerr << "libsodium init failed\n";
        return;
    }
    WsUrl parsed;
    if (!ParseWsUrl(ws_url_, &parsed)) {
        std::cerr << "Unsupported WebSocket URL (expected ws:// or wss://)\n";
        return;
    }
    socket_fd_ = ConnectTcp(parsed);
    if (socket_fd_ < 0) {
        std::cerr << "Failed to connect to gateway\n";
        return;
    }
    if (parsed.tls) {
        if (!InitTls(parsed.host)) {
            std::cerr << "TLS initialization failed\n";
            CloseTransport();
            return;
        }
    }

    std::string ws_key = GenerateWsKey();
    std::ostringstream req;
    req << "GET " << parsed.path << " HTTP/1.1\r\n";
    req << "Host: " << parsed.host << ":" << parsed.port << "\r\n";
    req << "Upgrade: websocket\r\n";
    req << "Connection: Upgrade\r\n";
    req << "Sec-WebSocket-Key: " << ws_key << "\r\n";
    req << "Sec-WebSocket-Version: 13\r\n\r\n";
    std::string req_str = req.str();
    IoState io{socket_fd_, tls_, use_tls_};
    if (!WriteExact(&io, req_str.data(), req_str.size())) {
        std::cerr << "Failed to send websocket handshake\n";
        CloseTransport();
        return;
    }
    std::string response;
    if (!ReadHttpResponse(&io, &response)) {
        std::cerr << "Handshake response missing\n";
        CloseTransport();
        return;
    }
    if (!ValidateHandshake(response, ComputeAcceptKey(ws_key))) {
        std::cerr << "Handshake validation failed\n";
        CloseTransport();
        return;
    }

    start_time_ = std::time(nullptr);
    if (!SendAuth()) {
        std::cerr << "AUTH send failed\n";
        CloseTransport();
        return;
    }

    while (true) {
        fd_set readfds;
        FD_ZERO(&readfds);
        FD_SET(socket_fd_, &readfds);
        timeval timeout{};
        timeout.tv_sec = 1;
        int ready = select(socket_fd_ + 1, &readfds, nullptr, nullptr, &timeout);
        if (ready < 0) {
            break;
        }
        if (ready > 0 && FD_ISSET(socket_fd_, &readfds)) {
            std::string payload;
            uint8_t opcode = 0;
            if (!ReadWsFrame(&io, &payload, &opcode)) {
                break;
            }
            if (opcode == 0x8) {
                break;
            }
            if (opcode == 0x9) {
                SendWsFrame(&io, payload, 0xA);
                continue;
            }
            if (opcode == 0x1) {
                try {
                    if (!ProcessInbound(payload)) {
                        break;
                    }
                } catch (const std::exception &ex) {
                    std::cerr << "ProcessInbound failed: " << ex.what() << "\n";
                    break;
                }
                try {
                    if (!FlushOutbox()) {
                        break;
                    }
                } catch (const std::exception &ex) {
                    std::cerr << "FlushOutbox failed: " << ex.what() << "\n";
                    break;
                }
            }
        }

        auto now = std::time(nullptr);
        if (authenticated_ && heartbeat_interval_ > 0 && (now - last_heartbeat_) >= heartbeat_interval_) {
            try {
                if (!SendHeartbeat()) {
                    break;
                }
            } catch (const std::exception &ex) {
                std::cerr << "Heartbeat failed: " << ex.what() << "\n";
                break;
            }
            last_heartbeat_ = now;
        }
        if (authenticated_ && telemetry_interval_ > 0 && (now - last_telemetry_) >= telemetry_interval_) {
            try {
                if (!SendTelemetry()) {
                    break;
                }
            } catch (const std::exception &ex) {
                std::cerr << "Telemetry failed: " << ex.what() << "\n";
                break;
            }
            last_telemetry_ = now;
        }
        if (authenticated_) {
            try {
                if (!FlushOutbox()) {
                    break;
                }
            } catch (const std::exception &ex) {
                std::cerr << "Outbox flush failed: " << ex.what() << "\n";
                break;
            }
        }
    }
    CloseTransport();
}

}  // namespace quoodle
