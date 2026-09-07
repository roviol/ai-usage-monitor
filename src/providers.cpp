#include "ai_usage/providers.h"

#include <nlohmann/json.hpp>

#include <algorithm>
#include <array>
#include <atomic>
#include <cctype>
#include <cstdio>
#include <chrono>
#include <cmath>
#include <ctime>
#include <iomanip>
#include <map>
#include <regex>
#include <sstream>
#include <stdexcept>
#include <string_view>

namespace ai_usage {
namespace {

using Json = nlohmann::json;

std::string NumberText(const Json& value) {
  if (value.is_string()) {
    const auto text = value.get<std::string>();
    if (!IsDecimal(text)) throw std::runtime_error("expected decimal string");
    return text;
  }
  if (value.is_number_integer()) return std::to_string(value.get<std::int64_t>());
  if (value.is_number_unsigned()) return std::to_string(value.get<std::uint64_t>());
  if (value.is_number_float()) {
    const auto number = value.get<long double>();
    if (!std::isfinite(number)) throw std::runtime_error("non-finite numeric value");
    std::ostringstream output;
    output << std::fixed << std::setprecision(6) << number;
    auto text = output.str();
    while (!text.empty() && text.back() == '0') text.pop_back();
    if (!text.empty() && text.back() == '.') text.pop_back();
    return text.empty() ? "0" : text;
  }
  throw std::runtime_error("expected numeric value");
}

std::string DecimalSubtract(const std::string& left, const std::string& right) {
  return SubtractDecimals(left, right);
}

ProviderSnapshot BaseSnapshot(const ProviderConfig& config, TimePoint observedAt) {
  ProviderSnapshot snapshot;
  snapshot.providerId = config.id;
  snapshot.displayName = config.name;
  snapshot.kind = config.kind;
  snapshot.observedAt = observedAt;
  snapshot.freshness = Freshness::Fresh;
  snapshot.health = Health::Healthy;
  return snapshot;
}

Metric Unsupported(MetricKind kind, MetricUnit unit, MetricScope scope, std::string label) {
  return Metric{kind, "", unit, scope, Provenance::ProviderReported, Availability::Unsupported, std::nullopt, std::nullopt,
                std::move(label)};
}

std::string JoinUrl(std::string base, std::string path) {
  if (path.size() > 2048U || path.find("://") != std::string::npos) {
    throw std::runtime_error("provider route must be a bounded same-origin path");
  }
  while (!base.empty() && base.back() == '/') base.pop_back();
  if (path.empty() || path.front() != '/') path.insert(path.begin(), '/');
  return base + path;
}

std::optional<std::chrono::seconds> ParseRetryAfter(const HttpResponse& response) {
  for (const auto& [name, value] : response.headers) {
    std::string lowered = name;
    std::transform(lowered.begin(), lowered.end(), lowered.begin(), [](unsigned char character) { return static_cast<char>(std::tolower(character)); });
    if (lowered == "retry-after") {
      try {
        const auto seconds = std::stoll(value);
        if (seconds > 0) return std::chrono::seconds{seconds};
      } catch (...) {
        return std::nullopt;
      }
    }
  }
  return std::nullopt;
}

std::tm LocalTime(TimePoint value) {
  const auto raw = Clock::to_time_t(value);
  std::tm result{};
#ifdef _WIN32
  if (localtime_s(&result, &raw) != 0) throw std::runtime_error("cannot convert local time");
#else
  if (localtime_r(&raw, &result) == nullptr) throw std::runtime_error("cannot convert local time");
#endif
  return result;
}

std::optional<int> MonthIndex(std::string month) {
  static const std::array<std::string_view, 12> months{
      "jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"};
  std::transform(month.begin(), month.end(), month.begin(),
                 [](unsigned char character) { return static_cast<char>(std::tolower(character)); });
  const auto found = std::find(months.begin(), months.end(), month);
  if (found == months.end()) return std::nullopt;
  return static_cast<int>(std::distance(months.begin(), found));
}

std::optional<TimePoint> ParseClaudeReset(const std::string& line, TimePoint observedAt) {
  static const std::regex reset(
      R"(\b(?:resets|reinicia)\s+([A-Za-z]{3})\s+([0-9]{1,2}),?\s+([0-9]{1,2})(?::([0-9]{2}))?\s*(am|pm)\b)",
      std::regex::icase);
  std::smatch match;
  if (!std::regex_search(line, match, reset)) return std::nullopt;
  const auto month = MonthIndex(match[1].str());
  if (!month.has_value()) return std::nullopt;
  const int day = std::stoi(match[2].str());
  int hour = std::stoi(match[3].str());
  const int minute = match[4].matched ? std::stoi(match[4].str()) : 0;
  std::string meridiem = match[5].str();
  std::transform(meridiem.begin(), meridiem.end(), meridiem.begin(),
                 [](unsigned char character) { return static_cast<char>(std::tolower(character)); });
  if (day < 1 || day > 31 || hour < 1 || hour > 12 || minute < 0 || minute > 59) return std::nullopt;
  if (hour == 12) hour = 0;
  if (meridiem == "pm") hour += 12;

  auto candidate = LocalTime(observedAt);
  candidate.tm_mon = *month;
  candidate.tm_mday = day;
  candidate.tm_hour = hour;
  candidate.tm_min = minute;
  candidate.tm_sec = 0;
  candidate.tm_isdst = -1;
  auto raw = std::mktime(&candidate);
  if (raw == static_cast<std::time_t>(-1)) return std::nullopt;
  auto result = Clock::from_time_t(raw);
  if (result < observedAt) {
    ++candidate.tm_year;
    candidate.tm_isdst = -1;
    raw = std::mktime(&candidate);
    if (raw == static_cast<std::time_t>(-1)) return std::nullopt;
    result = Clock::from_time_t(raw);
  }
  const auto normalized = LocalTime(result);
  if (normalized.tm_mon != *month || normalized.tm_mday != day || normalized.tm_hour != hour ||
      normalized.tm_min != minute) {
    return std::nullopt;
  }
  return result;
}

void RequireHttpSuccess(const HttpResponse& response) {
  if (response.status >= 200 && response.status < 300) return;
  if (response.status == 401 || response.status == 403) {
    throw ProviderException(ProviderError{"unauthorized", "authentication rejected", false, std::nullopt});
  }
  if (response.status == 429) {
    throw ProviderException(ProviderError{"rate-limited", "rate limited", true, ParseRetryAfter(response)});
  }
  const bool transient = response.status >= 500;
  throw ProviderException(ProviderError{"http-" + std::to_string(response.status),
                                        "HTTP request failed with status " + std::to_string(response.status),
                                        transient, std::nullopt});
}

std::string ApiKey(const ProviderConfig& config, ISecretStore& secrets) {
  if (config.encryptedApiKey.empty()) return {};
  return secrets.Unprotect(config.encryptedApiKey);
}

std::string PlainTerminalText(const std::string& terminal) {
  std::string plain;
  for (std::size_t index = 0; index < terminal.size();) {
    const unsigned char character = static_cast<unsigned char>(terminal[index]);
    if (character == 0x1BU) {
      ++index;
      if (index < terminal.size() && terminal[index] == '[') {
        ++index;
        while (index < terminal.size()) {
          const unsigned char marker = static_cast<unsigned char>(terminal[index++]);
          if (marker >= 0x40U && marker <= 0x7EU) break;
        }
      } else if (index < terminal.size() && terminal[index] == ']') {
        ++index;
        while (index < terminal.size()) {
          if (terminal[index] == '\a') { ++index; break; }
          if (terminal[index] == '\x1b' && index + 1U < terminal.size() && terminal[index + 1U] == '\\') {
            index += 2U;
            break;
          }
          ++index;
        }
      } else if (index < terminal.size()) {
        ++index;
      }
      continue;
    }
    if (character == '\b') {
      if (!plain.empty()) plain.pop_back();
      ++index;
      continue;
    }
    if (character == '\r') {
      plain.push_back('\n');
      ++index;
      continue;
    }
    if (character < 0x20U && character != '\n' && character != '\t') {
      ++index;
      continue;
    }
    plain.push_back(terminal[index++]);
  }
  return plain;
}

class ProviderBase : public IUsageProvider {
 public:
  ProviderBase(ProviderConfig config, IHttpClient& http, IProcessRunner& process, ISecretStore& secrets)
      : config_(std::move(config)), http_(http), process_(process), secrets_(secrets) {}
  const ProviderConfig& Config() const override { return config_; }
  void Cancel() override { cancelled_ = true; }

 protected:
  void BeginRefresh() { cancelled_ = false; }
  std::function<bool()> CancellationProbe() { return [this] { return cancelled_.load(); }; }
  ProviderConfig config_;
  IHttpClient& http_;
  IProcessRunner& process_;
  ISecretStore& secrets_;
  std::atomic<bool> cancelled_{false};
};

class CodexProvider final : public ProviderBase {
 public:
  using ProviderBase::ProviderBase;
  ProviderCapabilities Capabilities() const override { return {true, true, false, true, "Codex app-server"}; }
  ConnectionTestResult TestConnection() override {
    const auto version = ProbeVersion(process_, config_.executable);
    return {!version.empty(), Capabilities(), version.empty() ? "No se pudo ejecutar Codex" : version};
  }
  ProviderSnapshot Refresh() override {
    BeginRefresh();
    const std::string requests =
        "{\"method\":\"initialize\",\"id\":1,\"params\":{\"clientInfo\":{\"name\":\"ai-usage-monitor\",\"title\":\"AI Usage Monitor\",\"version\":\"0.1.1\"},\"capabilities\":{}}}\n"
        "{\"method\":\"initialized\",\"params\":{}}\n"
        "{\"method\":\"account/read\",\"id\":2,\"params\":{\"refreshToken\":false}}\n"
        "{\"method\":\"account/rateLimits/read\",\"id\":3}\n"
        "{\"method\":\"account/usage/read\",\"id\":4}\n";
    const auto result = process_.Run(ProcessRequest{config_.executable, {"app-server", "--listen", "stdio://"}, requests,
                                                     std::chrono::milliseconds{10000}, CancellationProbe(),
                                                     std::chrono::milliseconds{3000}});
    if (result.timedOut) throw std::runtime_error("Codex app-server timed out");
    if (result.standardOutput.empty()) throw std::runtime_error("Codex app-server returned no JSONL");
    return ParseCodexResponses(config_, result.standardOutput, Clock::now());
  }
};

class DeepSeekProvider final : public ProviderBase {
 public:
  using ProviderBase::ProviderBase;
  ProviderCapabilities Capabilities() const override { return {false, false, true, false, "DeepSeek /user/balance"}; }
  ConnectionTestResult TestConnection() override {
    try {
      const auto snapshot = Refresh();
      return {snapshot.health != Health::Error, Capabilities(), "Saldo DeepSeek disponible"};
    } catch (const std::exception& error) {
      return {false, Capabilities(), error.what()};
    }
  }
  ProviderSnapshot Refresh() override {
    BeginRefresh();
    const auto key = ApiKey(config_, secrets_);
    if (key.empty()) throw std::runtime_error("DeepSeek API key is required");
    const auto base = config_.baseUrl.empty() ? "https://api.deepseek.com" : config_.baseUrl;
    HttpRequest request;
    request.url = JoinUrl(base, config_.balancePath.empty() ? "/user/balance" : config_.balancePath);
    request.headers["Authorization"] = "Bearer " + key;
    request.headers["Accept"] = "application/json";
    request.allowLoopbackHttp = config_.allowLoopbackHttp;
    const auto response = http_.Send(request);
    RequireHttpSuccess(response);
    return ParseDeepSeekBalance(config_, response.body, Clock::now());
  }
};

class GenericProvider final : public ProviderBase {
 public:
  using ProviderBase::ProviderBase;
  ProviderCapabilities Capabilities() const override {
    return {!config_.usagePath.empty(), config_.jsonPointers.contains("remaining_percent"), !config_.balancePath.empty(),
            config_.jsonPointers.contains("total_tokens"), "Mappings explícitos"};
  }
  ConnectionTestResult TestConnection() override {
    try {
      const auto key = ApiKey(config_, secrets_);
      HttpRequest request;
      request.url = JoinUrl(config_.baseUrl, "/models");
      if (!key.empty()) request.headers["Authorization"] = "Bearer " + key;
      request.allowLoopbackHttp = config_.allowLoopbackHttp;
      const auto response = http_.Send(request);
      RequireHttpSuccess(response);
      return {true, Capabilities(), "Endpoint compatible accesible"};
    } catch (const std::exception& error) {
      return {false, Capabilities(), error.what()};
    }
  }
  ProviderSnapshot Refresh() override {
    BeginRefresh();
    auto snapshot = BaseSnapshot(config_, Clock::now());
    const auto key = ApiKey(config_, secrets_);
    const std::string path = !config_.usagePath.empty() ? config_.usagePath : config_.balancePath;
    if (path.empty()) {
      const auto test = TestConnection();
      if (!test.success) throw std::runtime_error(test.message);
      snapshot.health = Health::Partial;
      snapshot.metrics.push_back(Unsupported(MetricKind::Balance, MetricUnit::Unknown, MetricScope::CurrentBalance, "Saldo"));
      snapshot.metrics.push_back(Unsupported(MetricKind::TotalTokens, MetricUnit::Tokens, MetricScope::BillingPeriod, "Uso"));
      return snapshot;
    }
    HttpRequest request;
    request.url = JoinUrl(config_.baseUrl, path);
    if (!key.empty()) request.headers["Authorization"] = "Bearer " + key;
    request.allowLoopbackHttp = config_.allowLoopbackHttp;
    const auto response = http_.Send(request);
    RequireHttpSuccess(response);
    snapshot.metrics = ParseGenericMetrics(config_, response.body);
    snapshot.health = snapshot.metrics.empty() ? Health::Partial : Health::Healthy;
    return snapshot;
  }
};

class ClaudeSubscriptionProvider final : public ProviderBase {
 public:
  using ProviderBase::ProviderBase;
  ProviderCapabilities Capabilities() const override {
    return {true, true, false, false, "claude /usage local no interactivo"};
  }
  ConnectionTestResult TestConnection() override {
    try {
      const auto snapshot = Refresh();
      return {snapshot.health == Health::Healthy, Capabilities(), "claude /usage disponible"};
    } catch (const std::exception& error) {
      return {false, Capabilities(), error.what()};
    }
  }
  ProviderSnapshot Refresh() override {
    BeginRefresh();
    if (config_.executable.empty()) throw std::runtime_error("Claude executable unavailable");
    const auto result = process_.Run(ProcessRequest{config_.executable, {"/usage"}, {},
                                                     std::chrono::milliseconds{10000}, CancellationProbe()});
    if (result.cancelled) throw std::runtime_error("claude /usage cancelled");
    if (result.timedOut) throw std::runtime_error("claude /usage timed out");
    if (result.exitCode != 0) throw std::runtime_error("claude /usage failed: " + result.standardError);
    const auto parsed = ParseClaudeUsageText(config_, result.standardOutput, Clock::now());
    if (!parsed.has_value()) throw std::runtime_error("claude /usage output schema is unsupported");
    return *parsed;
  }
};

constexpr const char* kOllamaCloudUsageUrl = "https://ollama.com/api/usage";

std::optional<TimePoint> ParseOllamaUnloadTime(const std::string& text) {
  // Ollama marshals this from a Go time.Time, so it arrives as RFC 3339 with
  // optional fractional seconds and either "Z" or a numeric offset. Written by
  // hand rather than with std::chrono::parse, which libstdc++ only ships from
  // GCC 14 on and would break the Ubuntu build.
  int year = 0;
  int month = 0;
  int day = 0;
  int hour = 0;
  int minute = 0;
  int second = 0;
  int consumed = 0;
  if (std::sscanf(text.c_str(), "%4d-%2d-%2dT%2d:%2d:%2d%n", &year, &month, &day, &hour, &minute,
                  &second, &consumed) != 6) {
    return std::nullopt;
  }
  if (month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59 || second > 60 ||
      hour < 0 || minute < 0 || second < 0) {
    return std::nullopt;
  }
  std::string rest = text.substr(static_cast<std::size_t>(consumed));
  if (!rest.empty() && rest.front() == '.') {
    const auto end = rest.find_first_not_of("0123456789", 1U);
    if (end == 1U) return std::nullopt;
    rest = end == std::string::npos ? std::string{} : rest.substr(end);
  }

  // RFC 3339 requires a zone; a bare local time would be ambiguous, so reject it.
  int offsetMinutes = 0;
  bool zoned = false;
  if (rest == "Z" || rest == "z") {
    zoned = true;
    rest.clear();
  } else if (rest.size() == 6U && (rest.front() == '+' || rest.front() == '-')) {
    int offsetHour = 0;
    int offsetMinute = 0;
    if (std::sscanf(rest.c_str() + 1, "%2d:%2d", &offsetHour, &offsetMinute) != 2) return std::nullopt;
    if (offsetHour < 0 || offsetHour > 23 || offsetMinute < 0 || offsetMinute > 59) return std::nullopt;
    offsetMinutes = offsetHour * 60 + offsetMinute;
    if (rest.front() == '-') offsetMinutes = -offsetMinutes;
    zoned = true;
    rest.clear();
  }
  if (!zoned || !rest.empty()) return std::nullopt;

  std::tm parts{};
  parts.tm_year = year - 1900;
  parts.tm_mon = month - 1;
  parts.tm_mday = day;
  parts.tm_hour = hour;
  parts.tm_min = minute;
  parts.tm_sec = second;
#ifdef _WIN32
  const auto raw = _mkgmtime(&parts);
#else
  const auto raw = timegm(&parts);
#endif
  if (raw == static_cast<std::time_t>(-1)) return std::nullopt;
  return Clock::from_time_t(raw) - std::chrono::minutes{offsetMinutes};
}

class OllamaProvider final : public ProviderBase {
 public:
  using ProviderBase::ProviderBase;
  ProviderCapabilities Capabilities() const override {
    const bool cloud = !config_.encryptedCloudKey.empty();
    return {cloud, cloud, false, false,
            cloud ? "Modelos cargados, plan y creditos mensuales; sin recuento de tokens"
                  : "Modelos cargados y plan; anada una API key de ollama.com para los creditos"};
  }
  ConnectionTestResult TestConnection() override {
    try {
      const auto snapshot = Refresh();
      return {snapshot.health == Health::Healthy, Capabilities(), "Ollama /api/ps disponible"};
    } catch (const std::exception& error) {
      return {false, Capabilities(), error.what()};
    }
  }
  ProviderSnapshot Refresh() override {
    BeginRefresh();
    if (config_.baseUrl.empty()) throw std::runtime_error("Ollama base URL is required");
    if (!IsSafeEndpointUrl(config_.baseUrl, config_.allowLoopbackHttp)) {
      throw std::runtime_error("Ollama endpoint must use HTTPS or enabled loopback HTTP");
    }
    HttpRequest request;
    request.url = JoinUrl(config_.baseUrl, "/api/ps");
    request.headers["Accept"] = "application/json";
    const auto key = ApiKey(config_, secrets_);
    if (!key.empty()) request.headers["Authorization"] = "Bearer " + key;
    request.allowLoopbackHttp = config_.allowLoopbackHttp;
    const auto response = http_.Send(request);
    RequireHttpSuccess(response);
    auto snapshot = ParseOllamaStatus(config_, response.body, Clock::now());
    snapshot.accountLabel = AccountLabel(key);
    AddCloudUsage(snapshot);
    return snapshot;
  }

 private:
  // The credits live on ollama.com, not on the configured server, so they use
  // their own credential and never the one held for the local endpoint. A
  // failure here degrades the snapshot to partial rather than discarding the
  // loaded-model observation that did succeed.
  void AddCloudUsage(ProviderSnapshot& snapshot) {
    if (config_.encryptedCloudKey.empty()) return;
    try {
      HttpRequest request;
      request.url = kOllamaCloudUsageUrl;
      request.headers["Accept"] = "application/json";
      request.headers["Authorization"] = "Bearer " + secrets_.Unprotect(config_.encryptedCloudKey);
      const auto response = http_.Send(request);
      RequireHttpSuccess(response);
      const auto metrics = ParseOllamaCloudUsage(response.body);
      snapshot.metrics.insert(snapshot.metrics.end(), metrics.begin(), metrics.end());
    } catch (const ProviderException& error) {
      snapshot.health = Health::Partial;
      snapshot.error = error.Error();
    } catch (const std::exception& error) {
      snapshot.health = Health::Partial;
      snapshot.error = ProviderError{"cloud-usage-failed", error.what(), true, std::nullopt};
    }
  }

  // Supplementary: /api/me only labels the snapshot with the signed-in account,
  // so a server without one must not turn a good observation into an error.
  std::string AccountLabel(const std::string& key) {
    try {
      HttpRequest request;
      request.method = "POST";
      request.url = JoinUrl(config_.baseUrl, "/api/me");
      request.headers["Accept"] = "application/json";
      if (!key.empty()) request.headers["Authorization"] = "Bearer " + key;
      request.allowLoopbackHttp = config_.allowLoopbackHttp;
      const auto response = http_.Send(request);
      if (response.status < 200 || response.status >= 300) return {};
      return ParseOllamaAccountLabel(response.body);
    } catch (const std::exception&) {
      return {};
    }
  }
};

void AddCodexWindow(std::vector<Metric>& metrics, const Json& window, const std::string& label) {
  if (!window.is_object() || !window.contains("usedPercent")) return;
  const auto used = NumberText(window["usedPercent"]);
  std::optional<TimePoint> reset;
  std::optional<std::chrono::seconds> duration;
  if (window.contains("resetsAt") && window["resetsAt"].is_number_integer()) {
    reset = TimePoint{std::chrono::seconds{window["resetsAt"].get<std::int64_t>()}};
  }
  if (window.contains("windowDurationMins") && window["windowDurationMins"].is_number_integer()) {
    duration = std::chrono::minutes{window["windowDurationMins"].get<std::int64_t>()};
  }
  metrics.push_back(Metric{MetricKind::UsedPercent, used, MetricUnit::Percent, MetricScope::RollingWindow,
                           Provenance::ProviderReported, Availability::Available, reset, duration, label + " usado"});
  metrics.push_back(Metric{MetricKind::RemainingPercent, DecimalSubtract("100", used), MetricUnit::Percent,
                           MetricScope::RollingWindow, Provenance::Derived, Availability::Available, reset, duration,
                           label + " restante"});
}

}  // namespace

ProviderSnapshot ParseCodexResponses(const ProviderConfig& config, const std::string& jsonLines, TimePoint observedAt) {
  auto snapshot = BaseSnapshot(config, observedAt);
  std::istringstream lines(jsonLines);
  std::string line;
  bool accountSeen = false;
  bool limitsSeen = false;
  while (std::getline(lines, line)) {
    if (line.empty()) continue;
    Json message;
    try { message = Json::parse(line); }
    catch (...) { throw std::runtime_error("Codex app-server returned malformed JSONL"); }
    if (!message.contains("id") || !message["id"].is_number_integer()) continue;
    const int id = message["id"].get<int>();
    if (message.contains("error")) {
      snapshot.health = Health::Error;
      snapshot.error = ProviderError{"codex-protocol", message["error"].dump(), false, std::nullopt};
      continue;
    }
    if (!message.contains("result")) continue;
    const auto& result = message["result"];
    if (id == 2) {
      accountSeen = true;
      if (!result.contains("account") || result["account"].is_null()) {
        snapshot.health = Health::Error;
        snapshot.error = ProviderError{"unauthorized", "Codex no tiene una cuenta autenticada", false, std::nullopt};
      } else {
        const auto& account = result["account"];
        if (account.contains("email") && account["email"].is_string()) snapshot.accountLabel = account["email"].get<std::string>();
        if (snapshot.accountLabel.empty() && account.contains("type")) snapshot.accountLabel = account["type"].get<std::string>();
      }
    } else if (id == 3) {
      limitsSeen = true;
      const Json* buckets = nullptr;
      if (result.contains("rateLimitsByLimitId") && result["rateLimitsByLimitId"].is_object()) buckets = &result["rateLimitsByLimitId"];
      if (buckets != nullptr) {
        for (const auto& [bucketId, bucket] : buckets->items()) {
          std::string label = bucketId == "codex" ? "Codex" : bucketId;
          if (bucket.contains("limitName") && bucket["limitName"].is_string()) {
            const auto reportedLabel = bucket["limitName"].get<std::string>();
            if (!reportedLabel.empty()) label = reportedLabel;
          }
          if (bucket.contains("primary")) AddCodexWindow(snapshot.metrics, bucket["primary"], label + " principal");
          if (bucket.contains("secondary") && !bucket["secondary"].is_null()) AddCodexWindow(snapshot.metrics, bucket["secondary"], label + " secundaria");
        }
      } else if (result.contains("rateLimits")) {
        const auto& bucket = result["rateLimits"];
        if (bucket.contains("primary")) AddCodexWindow(snapshot.metrics, bucket["primary"], "Codex principal");
        if (bucket.contains("secondary") && !bucket["secondary"].is_null()) AddCodexWindow(snapshot.metrics, bucket["secondary"], "Codex secundaria");
      }
    } else if (id == 4 && result.contains("summary") && result["summary"].is_object()) {
      const auto& summary = result["summary"];
      if (summary.contains("lifetimeTokens") && !summary["lifetimeTokens"].is_null()) {
        snapshot.metrics.push_back(Metric{MetricKind::TotalTokens, NumberText(summary["lifetimeTokens"]), MetricUnit::Tokens,
                                          MetricScope::Lifetime, Provenance::ProviderReported, Availability::Available,
                                          std::nullopt, std::nullopt, "Tokens acumulados"});
      }
    }
  }
  if (!accountSeen) throw std::runtime_error("Codex account response was not received");
  if (!limitsSeen && snapshot.health != Health::Error) snapshot.health = Health::Partial;
  if (snapshot.metrics.empty() && snapshot.health == Health::Healthy) snapshot.health = Health::Partial;
  return snapshot;
}

ProviderSnapshot ParseDeepSeekBalance(const ProviderConfig& config, const std::string& json, TimePoint observedAt) {
  auto snapshot = BaseSnapshot(config, observedAt);
  const auto root = Json::parse(json);
  if (!root.contains("is_available") || !root["is_available"].is_boolean()) throw std::runtime_error("DeepSeek schema: is_available missing");
  if (!root.contains("balance_infos") || !root["balance_infos"].is_array()) throw std::runtime_error("DeepSeek schema: balance_infos missing");
  for (const auto& balance : root["balance_infos"]) {
    const auto currency = balance.at("currency").get<std::string>();
    const auto value = NumberText(balance.at("total_balance"));
    const auto unit = currency == "USD" ? MetricUnit::USD : currency == "CNY" ? MetricUnit::CNY : MetricUnit::Unknown;
    snapshot.metrics.push_back(Metric{MetricKind::Balance, value, unit, MetricScope::CurrentBalance,
                                      Provenance::ProviderReported, Availability::Available, std::nullopt, std::nullopt,
                                      "Saldo " + currency});
    if (config.budget.has_value() && unit != MetricUnit::Unknown) {
      snapshot.metrics.push_back(Metric{MetricKind::Spent, DecimalSubtract(*config.budget, value), unit,
                                        MetricScope::BillingPeriod, Provenance::Derived, Availability::Available,
                                        std::nullopt, std::nullopt, "Consumido derivado " + currency});
    }
  }
  if (!root["is_available"].get<bool>()) {
    snapshot.health = Health::Partial;
    snapshot.error = ProviderError{"balance-unavailable", "DeepSeek reporta saldo no disponible", false, std::nullopt};
  }
  snapshot.metrics.push_back(Unsupported(MetricKind::TotalTokens, MetricUnit::Tokens, MetricScope::BillingPeriod, "Tokens usados"));
  return snapshot;
}

std::vector<Metric> ParseGenericMetrics(const ProviderConfig& config, const std::string& json) {
  const auto root = Json::parse(json);
  std::vector<Metric> metrics;
  const auto add = [&](const std::string& key, MetricKind kind, MetricUnit unit, MetricScope scope, const std::string& label) {
    const auto found = config.jsonPointers.find(key);
    if (found == config.jsonPointers.end() || found->second.empty()) return;
    const Json::json_pointer pointer(found->second);
    if (!root.contains(pointer)) throw std::runtime_error("JSON Pointer missing for " + key);
    metrics.push_back(Metric{kind, NumberText(root.at(pointer)), unit, scope, Provenance::ProviderReported,
                             Availability::Available, std::nullopt, std::nullopt, label});
  };
  add("used_percent", MetricKind::UsedPercent, MetricUnit::Percent, MetricScope::BillingPeriod, "Uso");
  add("remaining_percent", MetricKind::RemainingPercent, MetricUnit::Percent, MetricScope::BillingPeriod, "Restante");
  add("total_tokens", MetricKind::TotalTokens, MetricUnit::Tokens, MetricScope::BillingPeriod, "Tokens");
  add("balance_usd", MetricKind::Balance, MetricUnit::USD, MetricScope::CurrentBalance, "Saldo USD");
  add("balance_cny", MetricKind::Balance, MetricUnit::CNY, MetricScope::CurrentBalance, "Saldo CNY");
  add("spent_usd", MetricKind::Spent, MetricUnit::USD, MetricScope::BillingPeriod, "Consumido USD");
  return metrics;
}

std::optional<ProviderSnapshot> ParseClaudeUsageText(
    const ProviderConfig& config, const std::string& output, TimePoint observedAt) {
  static const std::regex percentage(
      R"((Current session|Current week(?: \(all models\))?)[^0-9\n]{0,40}([0-9]{1,3})%[^\n]*(?:used|usado)[^\n]*)",
      std::regex::icase);
  const auto plain = PlainTerminalText(output);
  auto snapshot = BaseSnapshot(config, observedAt);
  for (std::sregex_iterator match(plain.begin(), plain.end(), percentage), end; match != end; ++match) {
    const auto used = (*match)[2].str();
    if (std::stoll(used) > 100) return std::nullopt;
    const auto period = (*match)[1].str();
    const bool weekly = period.find("week") != std::string::npos || period.find("Week") != std::string::npos;
    const std::string label = weekly ? "Claude semana" : "Claude sesión";
    const auto reset = ParseClaudeReset((*match)[0].str(), observedAt);
    snapshot.metrics.push_back(Metric{MetricKind::UsedPercent, used, MetricUnit::Percent, MetricScope::RollingWindow,
                                      Provenance::CliBridge, Availability::Available, reset, std::nullopt,
                                      label + " usado"});
    snapshot.metrics.push_back(Metric{MetricKind::RemainingPercent, DecimalSubtract("100", used), MetricUnit::Percent,
                                      MetricScope::RollingWindow, Provenance::Derived, Availability::Available,
                                      reset, std::nullopt, label + " restante"});
  }
  if (snapshot.metrics.empty()) return std::nullopt;
  return snapshot;
}

std::vector<Metric> ParseOllamaCloudUsage(const std::string& json) {
  // ollama.com/api/usage reports the consumed share of the monthly allowance as
  // a 0..1 fraction, plus per-model request counts. It publishes no currency
  // amount and this adapter invents none: the fraction becomes a percentage,
  // the same shape every other provider's quota uses.
  std::vector<Metric> metrics;
  const auto root = Json::parse(json);
  if (!root.is_object()) throw std::runtime_error("Ollama usage schema: root must be an object");
  if (!root.contains("limits") || !root["limits"].is_object()) {
    throw std::runtime_error("Ollama usage schema: limits must be an object");
  }
  const auto& limits = root["limits"];
  if (!limits.contains("monthly") || !limits["monthly"].is_object()) {
    throw std::runtime_error("Ollama usage schema: monthly limits must be an object");
  }
  const auto& monthly = limits["monthly"];
  if (!monthly.contains("usage") || !monthly["usage"].is_number()) {
    throw std::runtime_error("Ollama usage schema: monthly usage must be a number");
  }
  const auto fraction = monthly["usage"].get<double>();
  if (!std::isfinite(fraction) || fraction < 0.0 || fraction > 1.0) {
    throw std::runtime_error("Ollama usage schema: monthly usage is outside 0..1");
  }

  const auto fixed = [](long double value, int decimals) {
    std::ostringstream text;
    text << std::fixed << std::setprecision(decimals) << value;
    return text.str();
  };
  const auto usedPercent = fixed(static_cast<long double>(fraction) * 100.0L, 1);
  metrics.push_back(Metric{MetricKind::UsedPercent, usedPercent, MetricUnit::Percent,
                           MetricScope::BillingPeriod, Provenance::ProviderReported, Availability::Available,
                           std::nullopt, std::nullopt, "Creditos mensuales usados"});
  metrics.push_back(Metric{MetricKind::RemainingPercent, SubtractDecimals("100.0", usedPercent),
                           MetricUnit::Percent, MetricScope::BillingPeriod, Provenance::Derived,
                           Availability::Available, std::nullopt, std::nullopt,
                           "Creditos mensuales restantes"});

  if (monthly.contains("models") && !monthly["models"].is_null()) {
    if (!monthly["models"].is_array()) {
      throw std::runtime_error("Ollama usage schema: monthly models must be an array");
    }
    for (const auto& model : monthly["models"]) {
      if (!model.is_object()) throw std::runtime_error("Ollama usage schema: model must be an object");
      if (!model.contains("name") || !model["name"].is_string()) {
        throw std::runtime_error("Ollama usage schema: model name missing");
      }
      const auto name = model["name"].get<std::string>();
      if (name.empty() || name.size() > 256U) throw std::runtime_error("Ollama usage schema: invalid model name");
      if (!model.contains("request_count") || !model["request_count"].is_number_integer()) {
        throw std::runtime_error("Ollama usage schema: request_count must be an integer");
      }
      const auto requests = model["request_count"].get<long long>();
      if (requests < 0) throw std::runtime_error("Ollama usage schema: negative request count");
      metrics.push_back(Metric{MetricKind::Requests, std::to_string(requests), MetricUnit::Requests,
                               MetricScope::BillingPeriod, Provenance::ProviderReported,
                               Availability::Available, std::nullopt, std::nullopt, name});
    }
  }
  return metrics;
}

std::string ParseOllamaAccountLabel(const std::string& json) {
  // Only the account name and plan are kept. The endpoint also returns an
  // e-mail address and identifiers that this snapshot has no use for, so they
  // are dropped rather than cached. Ollama publishes no credit figures here;
  // the plan name must never be turned into an allowance or a spend value.
  const auto printable = [](const std::string& value, std::size_t limit) {
    if (value.empty() || value.size() > limit) return false;
    return std::all_of(value.begin(), value.end(),
                       [](unsigned char c) { return c >= 0x20 && c != 0x7F; });
  };
  try {
    const auto root = Json::parse(json);
    if (!root.is_object()) return {};
    if (!root.contains("name") || !root["name"].is_string()) return {};
    const auto name = root["name"].get<std::string>();
    if (!printable(name, 128U)) return {};
    if (!root.contains("plan") || !root["plan"].is_string()) return name;
    const auto plan = root["plan"].get<std::string>();
    if (!printable(plan, 64U)) return name;
    return name + " (plan " + plan + ")";
  } catch (const std::exception&) {
    return {};
  }
}

ProviderSnapshot ParseOllamaStatus(
    const ProviderConfig& config, const std::string& json, TimePoint observedAt) {
  auto snapshot = BaseSnapshot(config, observedAt);
  const auto root = Json::parse(json);
  if (!root.is_object()) throw std::runtime_error("Ollama schema: root must be an object");
  if (root.contains("models") && !root["models"].is_array()) {
    throw std::runtime_error("Ollama schema: models must be an array");
  }

  std::size_t loaded = 0;
  snapshot.metrics.push_back(Metric{MetricKind::LoadedModels, "0", MetricUnit::Count,
                                    MetricScope::CurrentObservation, Provenance::ProviderReported,
                                    Availability::Available, std::nullopt, std::nullopt, "Modelos cargados"});
  if (root.contains("models")) {
    for (const auto& model : root["models"]) {
      if (!model.is_object()) throw std::runtime_error("Ollama schema: model must be an object");
      if (!model.contains("name") || !model["name"].is_string()) {
        throw std::runtime_error("Ollama schema: model name missing");
      }
      const auto name = model["name"].get<std::string>();
      if (name.empty() || name.size() > 256U) throw std::runtime_error("Ollama schema: invalid model name");
      ++loaded;

      Metric memory{MetricKind::ResourceMemory,
                    "",
                    MetricUnit::Bytes,
                    MetricScope::CurrentObservation,
                    Provenance::ProviderReported,
                    Availability::Unsupported,
                    std::nullopt,
                    std::nullopt,
                    name};
      if (model.contains("size_vram") && !model["size_vram"].is_null()) {
        const auto value = NumberText(model["size_vram"]);
        if (std::stold(value) < 0.0L) throw std::runtime_error("Ollama schema: negative memory value");
        memory.value = value;
        memory.availability = Availability::Available;
      }
      if (model.contains("expires_at") && !model["expires_at"].is_null()) {
        if (!model["expires_at"].is_string()) {
          throw std::runtime_error("Ollama schema: expires_at must be a string");
        }
        const auto unload = ParseOllamaUnloadTime(model["expires_at"].get<std::string>());
        if (!unload.has_value()) throw std::runtime_error("Ollama schema: invalid unload timestamp");
        if (*unload > observedAt) memory.resetsAt = *unload;
      }
      snapshot.metrics.push_back(std::move(memory));
    }
  }

  snapshot.metrics.front().value = std::to_string(loaded);
  return snapshot;
}

std::unique_ptr<IUsageProvider> CreateProvider(
    ProviderConfig config, IHttpClient& http, IProcessRunner& process, ISecretStore& secrets) {
  switch (config.kind) {
    case ProviderKind::Codex:
      return std::make_unique<CodexProvider>(std::move(config), http, process, secrets);
    case ProviderKind::ClaudeSubscription:
      return std::make_unique<ClaudeSubscriptionProvider>(std::move(config), http, process, secrets);
    case ProviderKind::DeepSeek:
      return std::make_unique<DeepSeekProvider>(std::move(config), http, process, secrets);
    case ProviderKind::OpenAiCompatible:
      return std::make_unique<GenericProvider>(std::move(config), http, process, secrets);
    case ProviderKind::Ollama:
      return std::make_unique<OllamaProvider>(std::move(config), http, process, secrets);
  }
  throw std::runtime_error("unsupported provider kind");
}

}  // namespace ai_usage
