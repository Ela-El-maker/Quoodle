#pragma once

#include <cstdint>
#include <string>

namespace command
{

struct ArtifactUploadTicket
{
  bool ok{false};
  std::string reason;
  std::string upload_url;
  std::string artifact_id;
  std::string upload_token;
};

struct ArtifactUploadResult
{
  bool ok{false};
  std::string reason;
  std::string artifact_url;
  std::string artifact_checksum;
};

struct ArtifactDownloadResult
{
  bool ok{false};
  std::string reason;
  std::uint64_t size_bytes{0};
};

class ArtifactClient
{
public:
  ArtifactUploadTicket request_upload(
      const std::string &base_url,
      const std::string &bearer_jwt,
      const std::string &command_id,
      const std::string &content_type,
      std::uint64_t size_bytes,
      std::uint32_t timeout_ms = 10000) const;

  ArtifactUploadResult upload_file(
      const std::string &upload_url,
      const std::string &bearer_jwt,
      const std::string &artifact_id,
      const std::string &upload_token,
      const std::string &file_path,
      std::uint32_t timeout_ms = 20000) const;

  ArtifactDownloadResult download_artifact_to_file(
      const std::string &base_url,
      const std::string &bearer_jwt,
      const std::string &artifact_id,
      const std::string &output_path,
      std::uint32_t timeout_ms = 30000) const;
};

} // namespace command
