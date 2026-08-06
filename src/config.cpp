#include "ai_usage/config.h"
#include "ai_usage/overlay.h"

#include <nlohmann/json.hpp>

#include <algorithm>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <stdexcept>
#include <string_view>

namespace ai_usage {
namespace {

using Json = nlohmann::json;

void ValidateObject(const Json& value, std::string_view context,
                    std::initializer_list<std::string_view> allowed,
                    std::initializer_list<std::string_view> required = {}) {
  if (!value.is_object()) throw std::runtime_error(std::string(context) + " must be an object");
  for (const auto& [key, field] : value.items()) {
    (void)field;
    const auto found = std::find(allowed.begin(), allowed.end(), key);
    if (found == allowed.end()) throw std::runtime_error(std::string(context) + " contains unknown field: " + key);
  }
  for (const auto field : required) {
    if (!value.contains(std::string(field))) {
      throw std::runtime_error(std::string(context) + " is missing field: " + std::string(field));
    }
  }
}

ProviderKind ParseProviderKind(const std::string& text) {
  if (text == "codex") return ProviderKind::Codex;
  if (text == "claude-subscription") return ProviderKind::ClaudeSubscription;
  if (text == "claude-api") return ProviderKind::ClaudeSubscription;
  if (text == "deepseek") return ProviderKind::DeepSeek;
  if (text == "openai-compatible") return ProviderKind::OpenAiCompatible;
  throw std::runtime_error("unknown provider kind");
}

template <typename Enum>
Enum ParseEnum(const std::string& text);

template <>
MetricKind ParseEnum<MetricKind>(const std::string& text) {
  if (text == "used-percent") return MetricKind::UsedPercent;
  if (text == "remaining-percent") return MetricKind::RemainingPercent;
  if (text == "input-tokens") return MetricKind::InputTokens;
  if (text == "output-tokens") return MetricKind::OutputTokens;
  if (text == "total-tokens") return MetricKind::TotalTokens;
  if (text == "balance") return MetricKind::Balance;
  if (text == "spent") return MetricKind::Spent;
  if (text == "requests") return MetricKind::Requests;
  throw std::runtime_error("unknown metric kind");
}

template <>
MetricUnit ParseEnum<MetricUnit>(const std::string& text) {
  if (text == "percent") return MetricUnit::Percent;
  if (text == "tokens") return MetricUnit::Tokens;
  if (text == "requests") return MetricUnit::Requests;
  if (text == "USD") return MetricUnit::USD;
  if (text == "CNY") return MetricUnit::CNY;
  if (text == "seconds") return MetricUnit::Seconds;
  if (text == "unknown") return MetricUnit::Unknown;
  throw std::runtime_error("unknown metric unit");
}

template <>
MetricScope ParseEnum<MetricScope>(const std::string& text) {
  if (text == "rolling-window") return MetricScope::RollingWindow;
  if (text == "day") return MetricScope::Day;
  if (text == "billing-period") return MetricScope::BillingPeriod;
  if (text == "lifetime") return MetricScope::Lifetime;
  if (text == "current-balance") return MetricScope::CurrentBalance;
  throw std::runtime_error("unknown metric scope");
}

template <>
Provenance ParseEnum<Provenance>(const std::string& text) {
  if (text == "provider-reported") return Provenance::ProviderReported;
  if (text == "cli-bridge") return Provenance::CliBridge;
  if (text == "locally-observed") return Provenance::LocallyObserved;
  if (text == "derived") return Provenance::Derived;
  throw std::runtime_error("unknown metric provenance");
}

template <>
Availability ParseEnum<Availability>(const std::string& text) {
  if (text == "available") return Availability::Available;
  if (text == "unsupported") return Availability::Unsupported;
  if (text == "unauthorized") return Availability::Unauthorized;
  if (text == "unavailable") return Availability::Unavailable;
  if (text == "disabled") return Availability::Disabled;
  throw std::runtime_error("unknown metric availability");
}

template <>
Freshness ParseEnum<Freshness>(const std::string& text) {
  if (text == "fresh") return Freshness::Fresh;
  if (text == "stale") return Freshness::Stale;
  if (text == "no-data") return Freshness::NoData;
  throw std::runtime_error("unknown snapshot freshness");
}

template <>
Health ParseEnum<Health>(const std::string& text) {
  if (text == "healthy") return Health::Healthy;
  if (text == "partial") return Health::Partial;
  if (text == "error") return Health::Error;
  if (text == "disabled") return Health::Disabled;
  throw std::runtime_error("unknown snapshot health");
}

Json ProviderToJson(const ProviderConfig& provider, bool redact) {
  Json result{{"id", provider.id}, {"name", provider.name}, {"kind", ToString(provider.kind)}, {"enabled", provider.enabled},
              {"executable", provider.executable.string()}, {"baseUrl", provider.baseUrl},
              {"encryptedApiKey", redact && !provider.encryptedApiKey.empty() ? "<protected>" : provider.encryptedApiKey},
              {"usagePath", provider.usagePath}, {"balancePath", provider.balancePath},
              {"jsonPointers", provider.jsonPointers},
              {"allowLoopbackHttp", provider.allowLoopbackHttp}};
  if (provider.budget.has_value()) result["budget"] = *provider.budget;
  return result;
}

ProviderConfig ProviderFromJson(const Json& value) {
  ValidateObject(value, "provider",
                 {"id", "name", "kind", "enabled", "executable", "baseUrl", "encryptedApiKey", "usagePath",
                  "balancePath", "jsonPointers", "budget", "claudeBridge", "allowLoopbackHttp"},
                 {"id", "name", "kind"});
  ProviderConfig provider;
  provider.id = value.at("id").get<std::string>();
  provider.name = value.at("name").get<std::string>();
  provider.kind = ParseProviderKind(value.at("kind").get<std::string>());
  provider.enabled = value.value("enabled", false);
  provider.executable = std::filesystem::path(value.value("executable", std::string{}));
  provider.baseUrl = value.value("baseUrl", std::string{});
  provider.encryptedApiKey = value.value("encryptedApiKey", std::string{});
  provider.usagePath = value.value("usagePath", std::string{});
  provider.balancePath = value.value("balancePath", std::string{});
  provider.jsonPointers = value.value("jsonPointers", std::map<std::string, std::string>{});
  if (value.contains("budget") && value["budget"].is_string()) provider.budget = value["budget"].get<std::string>();
  provider.allowLoopbackHttp = value.value("allowLoopbackHttp", false);
  return provider;
}

OverlayCorner ParseOverlayCorner(const Json& value) {
  if (!value.is_string()) return OverlayCorner::TopRight;
  const auto text = value.get<std::string>();
  if (text == "top-left") return OverlayCorner::TopLeft;
  if (text == "top-right") return OverlayCorner::TopRight;
  if (text == "bottom-left") return OverlayCorner::BottomLeft;
  if (text == "bottom-right") return OverlayCorner::BottomRight;
  return OverlayCorner::TopRight;
}

OverlaySettings OverlayFromJson(const Json& value) {
  OverlaySettings overlay;
  if (!value.is_object()) return overlay;
  if (const auto field = value.find("enabled"); field != value.end() && field->is_boolean()) {
    overlay.enabled = field->get<bool>();
  }
  if (const auto field = value.find("visible"); field != value.end() && field->is_boolean()) {
    overlay.visible = field->get<bool>();
  }
  if (const auto field = value.find("opacity"); field != value.end() && field->is_number_integer()) {
    overlay.opacity = NormalizeOverlayOpacity(field->get<int>());
  }
  if (const auto field = value.find("locked"); field != value.end() && field->is_boolean()) {
    overlay.locked = field->get<bool>();
  }
  if (const auto field = value.find("corner"); field != value.end()) overlay.corner = ParseOverlayCorner(*field);
  if (const auto field = value.find("monitor"); field != value.end() && field->is_string()) {
    overlay.monitor = field->get<std::string>();
    if (overlay.monitor.size() > 256U || std::any_of(overlay.monitor.begin(), overlay.monitor.end(),
                                                    [](unsigned char ch) { return ch < 0x20; })) {
      overlay.monitor.clear();
    }
  }
  if (const auto field = value.find("margin"); field != value.end() && field->is_number_integer()) {
    overlay.margin = NormalizeOverlayMargin(field->get<int>());
  }
  if (const auto field = value.find("suppressFullscreen");
      field != value.end() && field->is_boolean()) {
    overlay.suppressFullscreen = field->get<bool>();
  }
  return overlay;
}

Json OverlayToJson(const OverlaySettings& overlay) {
  return {{"enabled", overlay.enabled},
          {"visible", overlay.visible},
          {"opacity", NormalizeOverlayOpacity(overlay.opacity)},
          {"locked", overlay.locked},
          {"corner", ToString(overlay.corner)},
          {"monitor", overlay.monitor},
          {"margin", NormalizeOverlayMargin(overlay.margin)},
          {"suppressFullscreen", overlay.suppressFullscreen}};
}

Json SettingsToJson(const Settings& settings, bool redact) {
  Json providers = Json::array();
  for (const auto& provider : settings.providers) providers.push_back(ProviderToJson(provider, redact));
  return Json{{"schemaVersion", settings.schemaVersion}, {"refreshMinutes", settings.refreshMinutes},
              {"alwaysOnTop", settings.alwaysOnTop}, {"overlay", OverlayToJson(settings.overlay)},
              {"providers", providers}};
}

Settings SettingsFromJson(const Json& value) {
  ValidateObject(value, "settings", {"schemaVersion", "refreshMinutes", "alwaysOnTop", "overlay", "providers"},
                 {"schemaVersion"});
  Settings settings;
  settings.schemaVersion = value.at("schemaVersion").get<int>();
  settings.refreshMinutes = value.value("refreshMinutes", 5);
  settings.alwaysOnTop = value.value("alwaysOnTop", false);
  if (value.contains("overlay")) settings.overlay = OverlayFromJson(value.at("overlay"));
  const auto& providers = value.contains("providers") ? value.at("providers") : Json::array();
  if (!providers.is_array()) throw std::runtime_error("settings providers must be an array");
  for (const auto& provider : providers) settings.providers.push_back(ProviderFromJson(provider));
  const auto error = ValidateSettings(settings);
  if (error.has_value()) throw std::runtime_error(*error);
  return settings;
}

std::int64_t UnixSeconds(TimePoint value) {
  return std::chrono::duration_cast<std::chrono::seconds>(value.time_since_epoch()).count();
}

TimePoint FromUnix(std::int64_t value) { return TimePoint{std::chrono::seconds{value}}; }

Json MetricToJson(const Metric& metric) {
  Json result{{"kind", ToString(metric.kind)}, {"value", metric.value}, {"unit", ToString(metric.unit)},
              {"scope", ToString(metric.scope)}, {"provenance", ToString(metric.provenance)},
              {"availability", ToString(metric.availability)}, {"label", metric.label}};
  if (metric.resetsAt.has_value()) result["resetsAt"] = UnixSeconds(*metric.resetsAt);
  if (metric.window.has_value()) result["windowSeconds"] = metric.window->count();
  return result;
}

Metric MetricFromJson(const Json& value) {
  ValidateObject(value, "metric",
                 {"kind", "value", "unit", "scope", "provenance", "availability", "label", "resetsAt",
                  "windowSeconds"},
                 {"kind", "unit", "scope", "provenance", "availability"});
  Metric metric;
  metric.kind = ParseEnum<MetricKind>(value.at("kind").get<std::string>());
  metric.value = value.value("value", std::string{});
  metric.unit = ParseEnum<MetricUnit>(value.at("unit").get<std::string>());
  metric.scope = ParseEnum<MetricScope>(value.at("scope").get<std::string>());
  metric.provenance = ParseEnum<Provenance>(value.at("provenance").get<std::string>());
  metric.availability = ParseEnum<Availability>(value.at("availability").get<std::string>());
  metric.label = value.value("label", std::string{});
  if (value.contains("resetsAt")) metric.resetsAt = FromUnix(value["resetsAt"].get<std::int64_t>());
  if (value.contains("windowSeconds")) metric.window = std::chrono::seconds{value["windowSeconds"].get<std::int64_t>()};
  return metric;
}

Json SnapshotToJson(const ProviderSnapshot& snapshot) {
  Json metrics = Json::array();
  for (const auto& metric : snapshot.metrics) metrics.push_back(MetricToJson(metric));
  Json result{{"providerId", snapshot.providerId}, {"displayName", snapshot.displayName}, {"kind", ToString(snapshot.kind)},
              {"observedAt", UnixSeconds(snapshot.observedAt)}, {"freshness", ToString(snapshot.freshness)},
              {"health", ToString(snapshot.health)}, {"metrics", metrics}, {"accountLabel", snapshot.accountLabel}};
  if (snapshot.error.has_value()) {
    result["error"] = Json{{"code", snapshot.error->code}, {"message", snapshot.error->message},
                           {"transient", snapshot.error->transient}};
    if (snapshot.error->retryAfter.has_value()) result["error"]["retryAfter"] = snapshot.error->retryAfter->count();
  }
  return result;
}

ProviderSnapshot SnapshotFromJson(const Json& value) {
  ValidateObject(value, "snapshot",
                 {"providerId", "displayName", "kind", "observedAt", "freshness", "health", "metrics", "error",
                  "accountLabel"},
                 {"providerId", "displayName", "kind", "observedAt", "freshness", "health"});
  ProviderSnapshot snapshot;
  snapshot.providerId = value.at("providerId").get<std::string>();
  snapshot.displayName = value.at("displayName").get<std::string>();
  snapshot.kind = ParseProviderKind(value.at("kind").get<std::string>());
  snapshot.observedAt = FromUnix(value.at("observedAt").get<std::int64_t>());
  snapshot.freshness = ParseEnum<Freshness>(value.at("freshness").get<std::string>());
  snapshot.health = ParseEnum<Health>(value.at("health").get<std::string>());
  snapshot.accountLabel = value.value("accountLabel", std::string{});
  for (const auto& metric : value.value("metrics", Json::array())) snapshot.metrics.push_back(MetricFromJson(metric));
  if (value.contains("error")) {
    const auto& error = value["error"];
    ValidateObject(error, "provider error", {"code", "message", "transient", "retryAfter"});
    ProviderError parsed{error.value("code", "cached-error"), error.value("message", ""), error.value("transient", false), std::nullopt};
    if (error.contains("retryAfter")) parsed.retryAfter = std::chrono::seconds{error["retryAfter"].get<std::int64_t>()};
    snapshot.error = parsed;
  }
  return snapshot;
}

Json ReadJson(const std::filesystem::path& path) {
  std::ifstream input(path, std::ios::binary);
  if (!input) throw std::runtime_error("cannot open " + path.string());
  Json value;
  input >> value;
  return value;
}

void AtomicWrite(const std::filesystem::path& path, const std::string& content) {
  std::filesystem::create_directories(path.parent_path());
  const auto temporary = path.string() + ".tmp";
  const auto backup = path.string() + ".bak";
  {
    std::ofstream output(temporary, std::ios::binary | std::ios::trunc);
    if (!output) throw std::runtime_error("cannot write temporary file");
    output << content;
    output.flush();
    if (!output) throw std::runtime_error("cannot flush temporary file");
  }
  std::error_code error;
  std::filesystem::remove(backup, error);
  error.clear();
  if (std::filesystem::exists(path)) {
    std::filesystem::rename(path, backup, error);
    if (error) throw std::runtime_error("cannot rotate current file: " + error.message());
  }
  error.clear();
  std::filesystem::rename(temporary, path, error);
  if (error) {
    if (std::filesystem::exists(backup)) std::filesystem::rename(backup, path, error);
    throw std::runtime_error("cannot replace file atomically");
  }
}

std::filesystem::path UserDataRoot() {
#ifdef _WIN32
  wchar_t* value = nullptr;
  std::size_t length = 0;
  if (_wdupenv_s(&value, &length, L"LOCALAPPDATA") == 0 && value != nullptr) {
    const std::filesystem::path root(value);
    std::free(value);
    return root / "AIUsageMonitor";
  }
#else
  const char* xdg = std::getenv("XDG_DATA_HOME");
  if (xdg != nullptr) return std::filesystem::path(xdg) / "ai-usage-monitor";
  const char* userHome = std::getenv("HOME");
  if (userHome != nullptr) return std::filesystem::path(userHome) / ".local" / "share" / "ai-usage-monitor";
#endif
  return std::filesystem::temp_directory_path() / "ai-usage-monitor";
}

class DefaultFilesystemLocations final : public IFilesystemLocations {
 public:
  std::filesystem::path PerUserDataRoot() const override { return UserDataRoot(); }
};

std::optional<std::filesystem::path> DataDirectoryOverride() {
#ifdef _WIN32
  char* value = nullptr;
  std::size_t length = 0;
  if (_dupenv_s(&value, &length, "AI_USAGE_DATA_DIR") != 0 || value == nullptr) return std::nullopt;
  const std::filesystem::path result(value);
  std::free(value);
  if (result.empty()) return std::nullopt;
  return result;
#else
  const char* value = std::getenv("AI_USAGE_DATA_DIR");
  if (value == nullptr || *value == '\0') return std::nullopt;
  return std::filesystem::path(value);
#endif
}

std::vector<ProviderSnapshot> LoadCacheFile(const std::filesystem::path& path) {
  const auto root = ReadJson(path);
  ValidateObject(root, "cache", {"schemaVersion", "snapshots"}, {"schemaVersion"});
  if (root.at("schemaVersion").get<int>() != 1) throw std::runtime_error("unsupported cache schema");
  const auto& values = root.contains("snapshots") ? root.at("snapshots") : Json::array();
  if (!values.is_array()) throw std::runtime_error("cache snapshots must be an array");
  std::vector<ProviderSnapshot> snapshots;
  for (const auto& value : values) {
    auto snapshot = SnapshotFromJson(value);
    snapshot.freshness = Freshness::Stale;
    if (snapshot.health == Health::Healthy) snapshot.health = Health::Partial;
    snapshots.push_back(std::move(snapshot));
  }
  return snapshots;
}

}  // namespace

DataPaths ResolveDataPaths(const std::filesystem::path& executablePath, IFilesystemLocations* locations) {
  DataPaths paths;
  if (const auto overrideRoot = DataDirectoryOverride(); overrideRoot.has_value()) {
    paths.root = *overrideRoot;
    paths.portable = false;
    std::filesystem::create_directories(paths.root);
    paths.settings = paths.root / "settings.json";
    paths.cache = paths.root / "cache.json";
    return paths;
  }
  paths.root = executablePath.parent_path() / "data";
  std::error_code error;
  std::filesystem::create_directories(paths.root, error);
  const auto probe = paths.root / ".write-test";
  if (!error) {
    std::ofstream test(probe, std::ios::binary | std::ios::trunc);
    if (test) {
      test << "ok";
      test.close();
      std::filesystem::remove(probe, error);
    } else {
      error = std::make_error_code(std::errc::permission_denied);
    }
  }
  if (error) {
    DefaultFilesystemLocations defaults;
    paths.root = (locations == nullptr ? defaults.PerUserDataRoot() : locations->PerUserDataRoot());
    paths.portable = false;
    std::filesystem::create_directories(paths.root);
  }
  paths.settings = paths.root / "settings.json";
  paths.cache = paths.root / "cache.json";
  return paths;
}

LoadSettingsResult LoadSettings(const DataPaths& paths) {
  LoadSettingsResult result;
  if (!std::filesystem::exists(paths.settings)) return result;
  try {
    result.settings = SettingsFromJson(ReadJson(paths.settings));
    return result;
  } catch (const std::exception& currentError) {
    const auto backup = std::filesystem::path(paths.settings.string() + ".bak");
    if (!std::filesystem::exists(backup)) throw;
    result.settings = SettingsFromJson(ReadJson(backup));
    result.recoveredBackup = true;
    result.warning = std::string("Recovered settings backup after: ") + currentError.what();
    return result;
  }
}

void SaveSettings(const DataPaths& paths, const Settings& settings) {
  const auto error = ValidateSettings(settings);
  if (error.has_value()) throw std::runtime_error(*error);
  AtomicWrite(paths.settings, SettingsToJson(settings, false).dump(2));
}

std::vector<ProviderSnapshot> LoadCache(const DataPaths& paths) {
  if (!std::filesystem::exists(paths.cache)) return {};
  try {
    return LoadCacheFile(paths.cache);
  } catch (...) {
    const auto backup = std::filesystem::path(paths.cache.string() + ".bak");
    if (!std::filesystem::exists(backup)) return {};
    try { return LoadCacheFile(backup); } catch (...) { return {}; }
  }
}

void SaveCache(const DataPaths& paths, const std::vector<ProviderSnapshot>& snapshots) {
  Json values = Json::array();
  for (const auto& snapshot : snapshots) {
    if (ValidateSnapshot(snapshot).valid) values.push_back(SnapshotToJson(snapshot));
  }
  AtomicWrite(paths.cache, Json{{"schemaVersion", 1}, {"snapshots", values}}.dump(2));
}

std::string RedactedSettingsJson(const Settings& settings) { return SettingsToJson(settings, true).dump(2); }

std::optional<std::string> ValidateSettings(const Settings& settings) {
  if (settings.schemaVersion != 1) return "unsupported settings schema";
  if (settings.refreshMinutes < 1 || settings.refreshMinutes > 60) return "refreshMinutes must be between 1 and 60";
  if (settings.overlay.opacity < 50 || settings.overlay.opacity > 100) return "overlay opacity must be between 50 and 100";
  if (settings.overlay.margin < 0 || settings.overlay.margin > 96) return "overlay margin must be between 0 and 96";
  if (settings.overlay.monitor.size() > 256U) return "overlay monitor identifier is too long";
  for (const auto& provider : settings.providers) {
    if (provider.id.empty() || provider.name.empty()) return "provider id and name are required";
    if (provider.budget.has_value() && (!IsDecimal(*provider.budget) || provider.budget->starts_with('-'))) {
      return "provider budget must be a non-negative decimal";
    }
    for (const auto* route : {&provider.usagePath, &provider.balancePath}) {
      if (route->size() > 2048U || route->find("://") != std::string::npos ||
          (!route->empty() && route->front() != '/')) {
        return "provider routes must be bounded same-origin paths beginning with '/'";
      }
    }
    if (provider.jsonPointers.size() > 16U) return "a provider may define at most 16 JSON Pointer mappings";
    for (const auto& [name, pointer] : provider.jsonPointers) {
      (void)name;
      if (pointer.empty() || pointer.size() > 2048U || pointer.front() != '/') return "invalid JSON Pointer mapping";
      try { (void)Json::json_pointer(pointer); } catch (...) { return "invalid JSON Pointer mapping"; }
    }
  }
  return std::nullopt;
}

std::string ToString(OverlayCorner value) {
  switch (value) {
    case OverlayCorner::TopLeft: return "top-left";
    case OverlayCorner::TopRight: return "top-right";
    case OverlayCorner::BottomLeft: return "bottom-left";
    case OverlayCorner::BottomRight: return "bottom-right";
  }
  return "top-right";
}

}  // namespace ai_usage
