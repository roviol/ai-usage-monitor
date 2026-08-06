#pragma once

#include "ai_usage/overlay.h"

#include <filesystem>
#include <map>
#include <optional>
#include <string>
#include <vector>

namespace ai_usage {

struct OverlaySettings {
  bool enabled{false};
  bool visible{true};
  int opacity{78};
  bool locked{true};
  OverlayCorner corner{OverlayCorner::TopRight};
  std::string monitor;
  int margin{12};
  bool suppressFullscreen{false};
};

struct ProviderConfig {
  std::string id;
  std::string name;
  ProviderKind kind{ProviderKind::OpenAiCompatible};
  bool enabled{false};
  std::filesystem::path executable;
  std::string baseUrl;
  std::string encryptedApiKey;
  std::string usagePath;
  std::string balancePath;
  std::map<std::string, std::string> jsonPointers;
  std::optional<std::string> budget;
  bool allowLoopbackHttp{false};

  bool operator==(const ProviderConfig&) const = default;
};

struct Settings {
  int schemaVersion{1};
  int refreshMinutes{5};
  bool alwaysOnTop{false};
  OverlaySettings overlay;
  std::vector<ProviderConfig> providers;
};

struct DataPaths {
  std::filesystem::path root;
  std::filesystem::path settings;
  std::filesystem::path cache;
  bool portable{true};
};

class IFilesystemLocations {
 public:
  virtual ~IFilesystemLocations() = default;
  virtual std::filesystem::path PerUserDataRoot() const = 0;
};

struct LoadSettingsResult {
  Settings settings;
  bool recoveredBackup{false};
  std::string warning;
};

DataPaths ResolveDataPaths(const std::filesystem::path& executablePath, IFilesystemLocations* locations = nullptr);
std::filesystem::path MakeExecutableReferencePortable(
    const std::string& command, const std::filesystem::path& configured,
    const std::optional<std::filesystem::path>& discovered);
LoadSettingsResult LoadSettings(const DataPaths& paths);
void SaveSettings(const DataPaths& paths, const Settings& settings);
std::vector<ProviderSnapshot> LoadCache(const DataPaths& paths);
void SaveCache(const DataPaths& paths, const std::vector<ProviderSnapshot>& snapshots);
std::string RedactedSettingsJson(const Settings& settings);
std::optional<std::string> ValidateSettings(const Settings& settings);
std::string ToString(OverlayCorner value);

}  // namespace ai_usage
