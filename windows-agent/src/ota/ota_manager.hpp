#pragma once

#include <string>
#include <unordered_map>

class OTAManager {
public:
    void set_manifest(const std::unordered_map<std::string, std::string>& manifest) {
        manifest_ = manifest;
    }

    std::unordered_map<std::string, std::string> manifest() const {
        return manifest_;
    }

    std::string release_id() const {
        auto it = manifest_.find("release_id");
        if (it != manifest_.end()) return it->second;
        return {};
    }

    std::string version() const {
        auto it = manifest_.find("version");
        if (it != manifest_.end()) return it->second;
        return {};
    }

private:
    std::unordered_map<std::string, std::string> manifest_;
};
