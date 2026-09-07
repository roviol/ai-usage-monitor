#include "ai_usage/config.h"
#include "ai_usage/overlay.h"
#include "ai_usage/platform.h"
#include "ai_usage/presentation.h"
#include "ai_usage/providers.h"
#include "ai_usage/scheduler.h"
#include "ai_usage/tooltip.h"

#include <algorithm>
#include <atomic>
#include <condition_variable>
#include <cstdlib>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <functional>
#include <iostream>
#include <mutex>
#include <stdexcept>
#include <string>
#include <string_view>
#include <thread>
#include <vector>

#ifndef AI_USAGE_SOURCE_DIR
#define AI_USAGE_SOURCE_DIR "."
#endif

#ifndef AI_USAGE_TEST_SUITE
#define AI_USAGE_TEST_SUITE "unit"
#endif

namespace {

using namespace ai_usage;

int failures = 0;

#define CHECK(condition) do { if (!(condition)) { std::cerr << __FILE__ << ':' << __LINE__ << " CHECK failed: " #condition "\n"; ++failures; } } while (false)

std::string ReadFixture(const std::string& name) {
  const auto path = std::filesystem::path(AI_USAGE_SOURCE_DIR) / "tests" / "fixtures" / name;
  std::ifstream input(path, std::ios::binary);
  if (!input) throw std::runtime_error("fixture unavailable: " + path.string());
  return std::string(std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>());
}

void SetDataDirectoryOverride(const std::optional<std::filesystem::path>& value) {
#ifdef _WIN32
  _putenv_s("AI_USAGE_DATA_DIR", value.has_value() ? value->string().c_str() : "");
#else
  if (value.has_value()) {
    setenv("AI_USAGE_DATA_DIR", value->string().c_str(), 1);
  } else {
    unsetenv("AI_USAGE_DATA_DIR");
  }
#endif
}

struct FakeHttp final : IHttpClient {
  HttpResponse response;
  std::vector<HttpResponse> responses;
  std::vector<HttpRequest> requests;
  HttpRequest last;
  HttpResponse Send(const HttpRequest& request) override {
    last = request;
    requests.push_back(request);
    if (!responses.empty()) {
      const auto index = std::min(requests.size() - 1U, responses.size() - 1U);
      return responses[index];
    }
    return response;
  }
};

struct FakeProcess final : IProcessRunner {
  ProcessResult result;
  ProcessRequest last;
  ProcessResult Run(const ProcessRequest& request) override {
    last = request;
    return result;
  }
};

struct FakeSecrets final : ISecretStore {
  std::string Protect(const std::string& plain) override { return "protected:" + plain; }
  std::string ProtectSession(const std::string& plain) override { return "session:" + plain; }
  std::string Unprotect(const std::string& opaque) override { return opaque.starts_with("protected:") ? opaque.substr(10) : opaque; }
  bool PersistentAvailable() const override { return true; }
};

struct RefreshTracker {
  std::atomic<int> active{0};
  std::atomic<int> maximum{0};
  std::atomic<int> calls{0};
};

class TrackedProvider final : public IUsageProvider {
 public:
  TrackedProvider(std::string id, RefreshTracker& tracker, std::chrono::milliseconds duration)
      : config_{std::move(id), "Tracked", ProviderKind::OpenAiCompatible, true}, tracker_(tracker), duration_(duration) {}
  const ProviderConfig& Config() const override { return config_; }
  ProviderCapabilities Capabilities() const override { return {}; }
  ConnectionTestResult TestConnection() override { return {true, {}, "ok"}; }
  ProviderSnapshot Refresh() override {
    ++tracker_.calls;
    const int active = ++tracker_.active;
    int observed = tracker_.maximum.load();
    while (active > observed && !tracker_.maximum.compare_exchange_weak(observed, active)) {}
    std::this_thread::sleep_for(duration_);
    --tracker_.active;
    return ProviderSnapshot{config_.id, config_.name, config_.kind, Clock::now(), Freshness::Fresh, Health::Healthy};
  }

 private:
  ProviderConfig config_;
  RefreshTracker& tracker_;
  std::chrono::milliseconds duration_;
};

class FakeClock final : public IClock {
 public:
  explicit FakeClock(TimePoint now) : now_(now) {}
  TimePoint Now() const override {
    std::lock_guard lock(mutex_);
    return now_;
  }
  void Advance(std::chrono::seconds duration) {
    std::lock_guard lock(mutex_);
    now_ += duration;
  }

 private:
  mutable std::mutex mutex_;
  TimePoint now_;
};

class FailingProvider final : public IUsageProvider {
 public:
  FailingProvider(std::string id, ProviderError error, std::atomic<int>& calls)
      : config_{std::move(id), "Failing", ProviderKind::OpenAiCompatible, true}, error_(std::move(error)), calls_(calls) {}
  const ProviderConfig& Config() const override { return config_; }
  ProviderCapabilities Capabilities() const override { return {}; }
  ConnectionTestResult TestConnection() override { return {false, {}, error_.message}; }
  ProviderSnapshot Refresh() override {
    ++calls_;
    throw ProviderException(error_);
  }

 private:
  ProviderConfig config_;
  ProviderError error_;
  std::atomic<int>& calls_;
};

void TestDomainValidation() {
  ProviderSnapshot snapshot{"test", "Test", ProviderKind::DeepSeek, Clock::now(), Freshness::Fresh, Health::Healthy};
  snapshot.metrics.push_back(Metric{MetricKind::UsedPercent, "101", MetricUnit::Percent, MetricScope::RollingWindow});
  CHECK(!ValidateSnapshot(snapshot).valid);
  snapshot.metrics[0].value = "33.5";
  CHECK(ValidateSnapshot(snapshot).valid);
  snapshot.metrics[0].value = "NaN";
  CHECK(!ValidateSnapshot(snapshot).valid);
}

void TestAggregate() {
  ProviderSnapshot healthy{"a", "A", ProviderKind::Codex, Clock::now(), Freshness::Fresh, Health::Healthy};
  ProviderSnapshot partial{"b", "B", ProviderKind::DeepSeek, Clock::now(), Freshness::Stale, Health::Partial};
  ProviderSnapshot disabled{"c", "C", ProviderKind::OpenAiCompatible, Clock::now(), Freshness::NoData,
                            Health::Disabled};
  CHECK(AggregateHealth({}) == Health::Disabled);
  CHECK(AggregateHealth({disabled}) == Health::Disabled);
  CHECK(AggregateHealth({healthy}) == Health::Healthy);
  healthy.freshness = Freshness::Stale;
  CHECK(AggregateHealth({healthy}) == Health::Partial);
  healthy.freshness = Freshness::Fresh;
  CHECK(AggregateHealth({healthy, partial}) == Health::Partial);
  partial.health = Health::Error;
  CHECK(AggregateHealth({healthy, partial}) == Health::Error);

  const Metric first{MetricKind::Balance, "0.10", MetricUnit::USD, MetricScope::CurrentBalance};
  Metric second = first;
  second.value = "0.20";
  const auto compatible = AggregateMetrics({first, second});
  CHECK(compatible.valid);
  CHECK(compatible.metric.has_value());
  CHECK(compatible.metric->value == "0.3");
  second.unit = MetricUnit::CNY;
  CHECK(!AggregateMetrics({first, second}).valid);
  second = first;
  second.scope = MetricScope::BillingPeriod;
  CHECK(!AggregateMetrics({first, second}).valid);
  second = first;
  second.provenance = Provenance::Derived;
  CHECK(!AggregateMetrics({first, second}).valid);
}

void TestCodexParser() {
  ProviderConfig config{"codex", "Codex", ProviderKind::Codex, true};
  const auto snapshot = ParseCodexResponses(config, ReadFixture("codex_multi_window.jsonl"), Clock::now());
  CHECK(snapshot.health == Health::Healthy);
  CHECK(snapshot.accountLabel == "dev@example.com");
  CHECK(snapshot.metrics.size() == 5U);
  CHECK(snapshot.metrics[0].label == "Codex principal usado");
  CHECK(snapshot.metrics[1].provenance == Provenance::Derived);
  const auto unauthorized = ParseCodexResponses(config, ReadFixture("codex_unauthorized.jsonl"), Clock::now());
  CHECK(unauthorized.health == Health::Error);
  CHECK(unauthorized.error.has_value());
  const auto partial = ParseCodexResponses(
      config,
      "{\"id\":1,\"result\":{}}\n{\"id\":2,\"result\":{\"account\":{\"type\":\"apiKey\"}}}\n"
      "{\"id\":3,\"result\":{\"rateLimits\":null}}\n{\"id\":4,\"result\":{}}\n",
      Clock::now());
  CHECK(partial.health == Health::Partial);
  CHECK(partial.accountLabel == "apiKey");
  bool malformedRejected = false;
  try { (void)ParseCodexResponses(config, "{not-json}\n", Clock::now()); } catch (...) { malformedRejected = true; }
  CHECK(malformedRejected);
}

void TestDeepSeekParser() {
  ProviderConfig config{"deepseek", "DeepSeek", ProviderKind::DeepSeek, true};
  config.budget = "100.00";
  const auto snapshot = ParseDeepSeekBalance(config, ReadFixture("deepseek_balance.json"), Clock::now());
  CHECK(snapshot.metrics.size() == 5U);
  CHECK(snapshot.metrics[0].value == "42.50");
  CHECK(snapshot.metrics[1].value == "57.5");
  CHECK(snapshot.metrics[1].provenance == Provenance::Derived);
}

void TestClaudeParser() {
  ProviderConfig config{"claude", "Claude", ProviderKind::ClaudeSubscription, true};
  std::tm observedLocal{};
  observedLocal.tm_year = 2026 - 1900;
  observedLocal.tm_mon = 7;
  observedLocal.tm_mday = 5;
  observedLocal.tm_hour = 18;
  observedLocal.tm_isdst = -1;
  const auto observedAt = Clock::from_time_t(std::mktime(&observedLocal));
  const auto usage = ParseClaudeUsageText(config, ReadFixture("claude_usage_screen.txt"), observedAt);
  CHECK(usage.has_value());
  CHECK(usage->metrics.size() == 4U);
  CHECK(usage->metrics[0].value == "37");
  CHECK(usage->metrics[1].value == "63");
  CHECK(usage->metrics[2].value == "61");
  CHECK(usage->metrics[3].value == "39");
  CHECK(usage->metrics[0].resetsAt.has_value());
  CHECK(usage->metrics[1].resetsAt == usage->metrics[0].resetsAt);
  CHECK(usage->metrics[2].resetsAt.has_value());
  CHECK(usage->metrics[3].resetsAt == usage->metrics[2].resetsAt);
  const auto sessionReset = Clock::to_time_t(*usage->metrics[0].resetsAt);
  const auto weeklyReset = Clock::to_time_t(*usage->metrics[2].resetsAt);
  std::tm sessionLocal{};
  std::tm weeklyLocal{};
#ifdef _WIN32
  CHECK(localtime_s(&sessionLocal, &sessionReset) == 0);
  CHECK(localtime_s(&weeklyLocal, &weeklyReset) == 0);
#else
  CHECK(localtime_r(&sessionReset, &sessionLocal) != nullptr);
  CHECK(localtime_r(&weeklyReset, &weeklyLocal) != nullptr);
#endif
  CHECK(sessionLocal.tm_mon == 7 && sessionLocal.tm_mday == 5 && sessionLocal.tm_hour == 19 && sessionLocal.tm_min == 10);
  CHECK(weeklyLocal.tm_mon == 7 && weeklyLocal.tm_mday == 7 && weeklyLocal.tm_hour == 21 && weeklyLocal.tm_min == 0);
  CHECK(!ParseClaudeUsageText(config, "ordinary model response", Clock::now()).has_value());
}

void TestClaudeBridge() {
  FakeHttp http;
  FakeProcess process;
  FakeSecrets secrets;
  process.result = ProcessResult{0, ReadFixture("claude_usage_screen.txt"), {}, false};
  ProviderConfig config{"claude", "Claude", ProviderKind::ClaudeSubscription, true};
  config.executable = "claude.exe";
  auto provider = CreateProvider(config, http, process, secrets);
  const auto snapshot = provider->Refresh();
  CHECK(snapshot.health == Health::Healthy);
  CHECK(process.last.arguments.size() == 1U);
  CHECK(process.last.arguments[0] == "/usage");
  CHECK(process.last.standardInput.empty());
  CHECK(snapshot.metrics.size() == 4U);
  CHECK(snapshot.metrics[0].value == "37");
}

void TestGenericParser() {
  ProviderConfig config{"generic", "Generic", ProviderKind::OpenAiCompatible, true};
  config.jsonPointers = {{"total_tokens", "/usage/total_tokens"}, {"used_percent", "/usage/used_percent"},
                         {"balance_usd", "/billing/balance"}};
  const auto metrics = ParseGenericMetrics(config, ReadFixture("generic_usage.json"));
  CHECK(metrics.size() == 3U);
  CHECK(metrics[0].value == "33");
  config.jsonPointers["balance_usd"] = "/missing";
  bool rejected = false;
  try { (void)ParseGenericMetrics(config, ReadFixture("generic_usage.json")); } catch (...) { rejected = true; }
  CHECK(rejected);
}

void TestOllamaParser() {
  ProviderConfig config{"ollama", "Ollama", ProviderKind::Ollama, true};
  const auto idle = ParseOllamaStatus(config, ReadFixture("ollama_idle.json"), Clock::now());
  CHECK(idle.health == Health::Healthy);
  CHECK(idle.metrics.size() == 1U);
  CHECK(idle.metrics[0].kind == MetricKind::LoadedModels);
  CHECK(idle.metrics[0].value == "0");

  const auto loaded = ParseOllamaStatus(config, ReadFixture("ollama_loaded.json"), Clock::now());
  CHECK(loaded.health == Health::Healthy);
  CHECK(loaded.metrics.size() == 2U);
  CHECK(loaded.metrics[0].kind == MetricKind::LoadedModels);
  CHECK(loaded.metrics[0].value == "1");
  CHECK(loaded.metrics[1].kind == MetricKind::ResourceMemory);
  CHECK(loaded.metrics[1].unit == MetricUnit::Bytes);
  CHECK(loaded.metrics[1].value == "1234567890");
  CHECK(loaded.metrics[1].label == "llama3.1:latest");

  const auto multi = ParseOllamaStatus(config, ReadFixture("ollama_multi.json"), Clock::now());
  CHECK(multi.metrics.size() == 3U);
  CHECK(multi.metrics[0].value == "2");
  CHECK(multi.metrics[1].value == "1234567890");
  CHECK(multi.metrics[2].availability == Availability::Unsupported);

  bool malformedRejected = false;
  try { (void)ParseOllamaStatus(config, R"({"models":{}})", Clock::now()); } catch (...) { malformedRejected = true; }
  CHECK(malformedRejected);
  bool badTimestampRejected = false;
  try {
    (void)ParseOllamaStatus(config, R"({"models":[{"name":"m","expires_at":"not-a-time"}]})", Clock::now());
  } catch (...) { badTimestampRejected = true; }
  CHECK(badTimestampRejected);
}

void TestSettingsAndCache() {
  const auto discoveredClaude = std::filesystem::path(R"(C:\Users\example\.local\bin\claude.exe)");
  CHECK(MakeExecutableReferencePortable("claude", discoveredClaude, discoveredClaude) ==
        std::filesystem::path("claude"));
  CHECK(MakeExecutableReferencePortable("claude", "claude", discoveredClaude) ==
        std::filesystem::path("claude"));
  CHECK(MakeExecutableReferencePortable("claude", R"(D:\tools\claude-wrapper.exe)", discoveredClaude) ==
        std::filesystem::path(R"(D:\tools\claude-wrapper.exe)"));

  const auto root = std::filesystem::temp_directory_path() / ("ai-usage-test-" + std::to_string(Clock::now().time_since_epoch().count()));
  std::filesystem::create_directories(root);
  const DataPaths paths{root, root / "settings.json", root / "cache.json", true};
  Settings settings;
  settings.refreshMinutes = 7;
  ProviderConfig provider{"deepseek", "DeepSeek", ProviderKind::DeepSeek, true};
  provider.encryptedApiKey = "protected:not-plaintext";
  settings.providers.push_back(provider);
  SaveSettings(paths, settings);
  CHECK(LoadSettings(paths).settings.refreshMinutes == 7);
  CHECK(RedactedSettingsJson(settings).find("<protected>") != std::string::npos);
  CHECK(RedactedSettingsJson(settings).find("not-plaintext") == std::string::npos);
  ProviderSnapshot snapshot{"deepseek", "DeepSeek", ProviderKind::DeepSeek, Clock::now(), Freshness::Fresh, Health::Healthy};
  snapshot.metrics.push_back(Metric{MetricKind::Balance, "1.25", MetricUnit::USD, MetricScope::CurrentBalance});
  SaveCache(paths, {snapshot});
  const auto cache = LoadCache(paths);
  CHECK(cache.size() == 1U);
  CHECK(cache[0].freshness == Freshness::Stale);

  snapshot.metrics[0].value = "2.50";
  SaveCache(paths, {snapshot});
  {
    std::ofstream interrupted(paths.cache, std::ios::binary | std::ios::trunc);
    interrupted << "{interrupted";
  }
  const auto recoveredCache = LoadCache(paths);
  CHECK(recoveredCache.size() == 1U);
  CHECK(recoveredCache[0].metrics[0].value == "1.25");

  settings.refreshMinutes = 8;
  SaveSettings(paths, settings);
  {
    std::ofstream interrupted(paths.settings, std::ios::binary | std::ios::trunc);
    interrupted << "{interrupted";
  }
  const auto recovered = LoadSettings(paths);
  CHECK(recovered.recoveredBackup);
  CHECK(recovered.settings.refreshMinutes == 7);

  std::filesystem::remove(std::filesystem::path(paths.settings.string() + ".bak"));
  {
    std::ofstream invalid(paths.settings, std::ios::binary | std::ios::trunc);
    invalid << R"({"schemaVersion":1,"providers":[],"unexpected":true})";
  }
  bool strictDecodeRejected = false;
  try { (void)LoadSettings(paths); } catch (...) { strictDecodeRejected = true; }
  CHECK(strictDecodeRejected);

  Settings workflow;
  workflow.alwaysOnTop = true;
  ProviderConfig disabled{"disabled", "Disabled", ProviderKind::OpenAiCompatible, false};
  disabled.baseUrl = "https://example.test";
  workflow.providers.push_back(disabled);
  SaveSettings(paths, workflow);
  const auto restoredWorkflow = LoadSettings(paths).settings;
  CHECK(restoredWorkflow.alwaysOnTop);
  CHECK(!restoredWorkflow.providers[0].enabled);

  workflow.overlay = OverlaySettings{true, false, 64, false, OverlayCorner::BottomLeft,
                                     R"(\\.\DISPLAY2)", 20, true};
  SaveSettings(paths, workflow);
  const auto restoredOverlay = LoadSettings(paths).settings;
  CHECK(restoredOverlay.overlay.enabled);
  CHECK(!restoredOverlay.overlay.visible);
  CHECK(restoredOverlay.overlay.opacity == 64);
  CHECK(!restoredOverlay.overlay.locked);
  CHECK(restoredOverlay.overlay.corner == OverlayCorner::BottomLeft);
  CHECK(restoredOverlay.overlay.monitor == R"(\\.\DISPLAY2)");
  CHECK(restoredOverlay.overlay.margin == 20);
  CHECK(restoredOverlay.overlay.suppressFullscreen);
  CHECK(restoredOverlay.providers[0].baseUrl == "https://example.test");

  {
    std::ofstream legacy(paths.settings, std::ios::binary | std::ios::trunc);
    legacy << R"({"schemaVersion":1,"refreshMinutes":9,"alwaysOnTop":true,"providers":[]})";
  }
  const auto legacy = LoadSettings(paths).settings;
  CHECK(!legacy.overlay.enabled);
  CHECK(legacy.overlay.visible);
  CHECK(legacy.overlay.opacity == 78);

  {
    std::ofstream malformed(paths.settings, std::ios::binary | std::ios::trunc);
    malformed << R"({"schemaVersion":1,"overlay":{"enabled":true,"opacity":4,"corner":7,"monitor":[],"margin":999,"locked":"yes"},"providers":[{"id":"safe","name":"Safe","kind":"deepseek","encryptedApiKey":"protected:kept"}]})";
  }
  const auto normalized = LoadSettings(paths).settings;
  CHECK(normalized.overlay.enabled);
  CHECK(normalized.overlay.opacity == 50);
  CHECK(normalized.overlay.corner == OverlayCorner::TopRight);
  CHECK(normalized.overlay.monitor.empty());
  CHECK(normalized.overlay.margin == 96);
  CHECK(normalized.overlay.locked);
  CHECK(normalized.providers[0].encryptedApiKey == "protected:kept");
  workflow.providers[0].usagePath = "https://other-origin.test/usage";
  CHECK(ValidateSettings(workflow).has_value());
  workflow.providers[0].usagePath = "/usage";
  workflow.providers[0].jsonPointers["total_tokens"] = "not-a-pointer";
  CHECK(ValidateSettings(workflow).has_value());

  const auto overrideRoot = root / "isolated-measurement";
  SetDataDirectoryOverride(overrideRoot);
  const auto overridden = ResolveDataPaths(root / "writable" / "ai-usage-monitor.exe");
  SetDataDirectoryOverride(std::nullopt);
  CHECK(overridden.root == overrideRoot);
  CHECK(!overridden.portable);
  std::error_code error;
  std::filesystem::remove_all(root, error);
}

void TestOllamaSettingsAndCache() {
  const auto root = std::filesystem::temp_directory_path() /
                    ("ai-usage-ollama-test-" + std::to_string(Clock::now().time_since_epoch().count()));
  std::filesystem::create_directories(root);
  const DataPaths paths{root, root / "settings.json", root / "cache.json", true};
  ProviderConfig provider{"ollama-local", "Ollama", ProviderKind::Ollama, false};
  provider.baseUrl = "http://localhost:11434";
  provider.encryptedApiKey = "protected:ollama-secret";
  provider.allowLoopbackHttp = true;
  Settings settings;
  settings.providers.push_back(provider);
  SaveSettings(paths, settings);
  const auto restored = LoadSettings(paths).settings;
  CHECK(restored.providers.size() == 1U);
  CHECK(restored.providers[0].kind == ProviderKind::Ollama);
  CHECK(restored.providers[0].baseUrl == "http://localhost:11434");
  CHECK(restored.providers[0].allowLoopbackHttp);
  CHECK(restored.providers[0].encryptedApiKey == "protected:ollama-secret");
  CHECK(RedactedSettingsJson(restored).find("ollama-secret") == std::string::npos);

  ProviderConfig missingUrl = provider;
  missingUrl.baseUrl.clear();
  Settings invalid;
  invalid.providers.push_back(missingUrl);
  CHECK(ValidateSettings(invalid).has_value());

  ProviderSnapshot snapshot{"ollama-local", "Ollama", ProviderKind::Ollama, Clock::now(),
                            Freshness::Fresh, Health::Healthy};
  Metric count{MetricKind::LoadedModels, "2", MetricUnit::Count, MetricScope::CurrentObservation};
  Metric memory{MetricKind::ResourceMemory, "1234567890", MetricUnit::Bytes, MetricScope::CurrentObservation};
  memory.label = "llama3.1:latest";
  memory.resetsAt = Clock::now() + std::chrono::minutes{3};
  snapshot.metrics.push_back(count);
  snapshot.metrics.push_back(memory);
  CHECK(ValidateSnapshot(snapshot).valid);
  SaveCache(paths, {snapshot});
  const auto cache = LoadCache(paths);
  CHECK(cache.size() == 1U);
  CHECK(cache[0].kind == ProviderKind::Ollama);
  CHECK(cache[0].metrics[0].kind == MetricKind::LoadedModels);
  CHECK(cache[0].metrics[0].unit == MetricUnit::Count);
  CHECK(cache[0].metrics[0].value == "2");
  CHECK(cache[0].metrics[1].kind == MetricKind::ResourceMemory);
  CHECK(cache[0].metrics[1].unit == MetricUnit::Bytes);
  CHECK(cache[0].metrics[1].value == "1234567890");
  CHECK(cache[0].metrics[1].resetsAt.has_value());

  snapshot.metrics[1].value = "-1";
  CHECK(!ValidateSnapshot(snapshot).valid);
  Metric mixed{MetricKind::ResourceMemory, "1", MetricUnit::Bytes, MetricScope::CurrentObservation};
  Metric other{MetricKind::LoadedModels, "1", MetricUnit::Count, MetricScope::CurrentObservation};
  CHECK(!AggregateMetrics({mixed, other}).valid);

  {
    std::ofstream legacy(paths.cache, std::ios::binary | std::ios::trunc);
    legacy << R"({"schemaVersion":1,"snapshots":[]})";
  }
  CHECK(LoadCache(paths).empty());

  std::error_code cleanup;
  std::filesystem::remove_all(root, cleanup);
}

void TestOverlayPresentationModel() {
  const auto now = TimePoint{std::chrono::seconds{6005}};
  Metric used{MetricKind::UsedPercent, "37", MetricUnit::Percent, MetricScope::RollingWindow};
  used.label = "Sesión 5 h";
  used.resetsAt = now + std::chrono::minutes{62};
  Metric remaining{MetricKind::RemainingPercent, "63", MetricUnit::Percent, MetricScope::RollingWindow};
  Metric balance{MetricKind::Balance, "12.50", MetricUnit::USD, MetricScope::CurrentBalance};
  balance.label = "Saldo";
  ProviderSnapshot claude{"claude", "Claude", ProviderKind::ClaudeSubscription, now,
                          Freshness::Stale, Health::Partial, {used, remaining, balance}};

  const auto complete = ProjectOverlayRows({claude}, now, 8);
  CHECK(complete.rows.size() == 2U);
  CHECK(complete.hiddenCount == 0U);
  CHECK(complete.rows[0].providerName == "Claude");
  CHECK(complete.rows[0].label == "Sesión 5 h");
  CHECK(complete.rows[0].usedPercent == 37.0);
  CHECK(complete.rows[0].resetText == "reinicia en 1h 2m");
  CHECK(complete.rows[0].statusText == "anterior");
  CHECK(!complete.rows[1].usedPercent.has_value());
  CHECK(complete.rows[1].value == "12.50 USD");

  auto overflowingClaude = claude;
  auto weekly = used;
  weekly.label = "Semana";
  overflowingClaude.metrics.push_back(weekly);
  const auto overflow = ProjectOverlayRows({overflowingClaude}, now, 2);
  CHECK(overflow.rows.size() == 1U);
  CHECK(overflow.hiddenCount == 2U);
  CHECK(OverlayRowCapacity(1000, 80, 32) == 10U);
  CHECK(OverlayRowCapacity(100, 80, 32) == 0U);
  CHECK(NormalizeOverlayOpacity(20) == 50);
  CHECK(NormalizeOverlayOpacity(120) == 100);
  CHECK(NormalizeOverlayOpacity(78) == 78);
  CHECK(NormalizeOverlayMargin(-1) == 0);
  CHECK(SelectOverlayMonitor("display-2", {"display-1", "display-2"}, "display-1") == "display-2");
  CHECK(SelectOverlayMonitor("missing", {"display-1", "display-2"}, "display-1") == "display-1");
  CHECK(SelectOverlayMonitor("missing", {"display-2"}, "missing-primary") == "display-2");
  CHECK(NearestOverlayCorner(15, 15, 300, 100, 0, 0, 1920, 1080, 12) == OverlayCorner::TopLeft);
  CHECK(NearestOverlayCorner(1600, 900, 300, 100, 0, 0, 1920, 1080, 12) == OverlayCorner::BottomRight);
  CHECK(CoversOverlayMonitor(0, 0, 1920, 1080, 0, 0, 1920, 1080));
  CHECK(!CoversOverlayMonitor(0, 0, 1920, 1040, 0, 0, 1920, 1080));
  CHECK(!CoversOverlayMonitor(1920, 0, 3840, 1080, 0, 0, 1920, 1080));

  CHECK(FormatResetCountdown(std::nullopt, now).empty());
  CHECK(FormatResetCountdown(now - std::chrono::seconds{1}, now) == "reiniciando");
  CHECK(FormatResetCountdown(now + std::chrono::seconds{20}, now) == "reinicia en <1m");
  CHECK(FormatResetCountdown(now + std::chrono::seconds{61}, now) == "reinicia en 2m");
  CHECK(FormatUnloadCountdown(std::nullopt, now).empty());
  CHECK(FormatUnloadCountdown(now - std::chrono::seconds{1}, now) == "descargando");
  CHECK(FormatUnloadCountdown(now + std::chrono::seconds{20}, now) == "descarga en <1m");
  CHECK(FormatUnloadCountdown(now + std::chrono::seconds{61}, now) == "descarga en 2m");

  ProviderSnapshot freshOllama{"ollama", "Ollama", ProviderKind::Ollama, now, Freshness::Fresh, Health::Healthy};
  Metric freshCount{MetricKind::LoadedModels, "1", MetricUnit::Count, MetricScope::CurrentObservation};
  freshCount.label = "Modelos cargados";
  Metric freshMemory{MetricKind::ResourceMemory, "1234", MetricUnit::Bytes,
                     MetricScope::CurrentObservation};
  freshMemory.label = "llama3.1:latest";
  freshMemory.resetsAt = now + std::chrono::seconds{61};
  freshOllama.metrics.push_back(freshCount);
  freshOllama.metrics.push_back(freshMemory);
  const auto freshRows = ProjectOverlayRows({freshOllama}, now, 8);
  CHECK(freshRows.rows.size() == 2U);
  CHECK(freshRows.rows[0].value == "1 modelo");
  CHECK(freshRows.rows[1].value == "1234 bytes");
  CHECK(freshRows.rows[1].resetText == "descarga en 2m");

  const auto staleRows = ProjectOverlayRows({freshOllama}, now, 8);
  CHECK(staleRows.rows.size() == 2U);
  freshOllama.freshness = Freshness::Stale;
  const auto staleAfter = ProjectOverlayRows({freshOllama}, now, 8);
  CHECK(staleAfter.rows[0].statusText == "anterior");

  ProviderSnapshot errorOllama{"ollama-error", "Ollama", ProviderKind::Ollama, now,
                               Freshness::Stale, Health::Error};
  errorOllama.error = ProviderError{"http-401", "authentication rejected", false, std::nullopt};
  const auto errorRows = ProjectOverlayRows({errorOllama}, now, 8);
  CHECK(errorRows.rows.size() == 1U);
  CHECK(errorRows.rows[0].statusText == "error · anterior");

  ProviderSnapshot idleOllama{"ollama-idle", "Ollama", ProviderKind::Ollama, now, Freshness::Fresh,
                              Health::Healthy};
  Metric idleCount{MetricKind::LoadedModels, "0", MetricUnit::Count, MetricScope::CurrentObservation};
  idleCount.label = "Modelos cargados";
  idleOllama.metrics.push_back(idleCount);
  const auto idleRows = ProjectOverlayRows({idleOllama}, now, 8);
  CHECK(idleRows.rows.size() == 1U);
  CHECK(idleRows.rows[0].value == "0 modelos");

  ProviderSnapshot multiOllama{"ollama-multi", "Ollama", ProviderKind::Ollama, now, Freshness::Fresh,
                               Health::Healthy};
  Metric multiCount{MetricKind::LoadedModels, "2", MetricUnit::Count, MetricScope::CurrentObservation};
  Metric memoryA{MetricKind::ResourceMemory, "1234", MetricUnit::Bytes, MetricScope::CurrentObservation};
  Metric memoryB{MetricKind::ResourceMemory, "2345", MetricUnit::Bytes, MetricScope::CurrentObservation};
  memoryA.label = "llama3.1:latest";
  memoryB.label = "qwen2.5-coder:7b";
  multiOllama.metrics.push_back(multiCount);
  multiOllama.metrics.push_back(memoryA);
  multiOllama.metrics.push_back(memoryB);
  const auto multiRows = ProjectOverlayRows({multiOllama}, now, 8);
  CHECK(multiRows.rows.size() == 3U);
  CHECK(multiRows.rows[0].value == "2 modelos");
  CHECK(multiRows.rows[1].label == "llama3.1:latest");
  CHECK(multiRows.rows[2].label == "qwen2.5-coder:7b");
  CHECK(NextOverlayCountdownUpdate(complete.rows, now) == TimePoint{std::chrono::seconds{6060}});
  auto imminent = complete.rows;
  imminent[0].resetsAt = now + std::chrono::seconds{20};
  CHECK(NextOverlayCountdownUpdate(imminent, now) == now + std::chrono::seconds{20});
  imminent[0].resetsAt = now;
  CHECK(!NextOverlayCountdownUpdate(imminent, now).has_value());
}

void TestSecurityHelpers() {
  CHECK(IsSafeEndpointUrl("https://api.deepseek.com", false));
  CHECK(!IsSafeEndpointUrl("http://api.deepseek.com", true));
  CHECK(IsSafeEndpointUrl("http://127.0.0.1:8080/v1", true));
  CHECK(!IsSafeEndpointUrl("http://127.0.0.1:8080/v1", false));
  const auto redacted = RedactSecrets("Authorization: Bearer secret\nkey=secret", {"secret"});
  CHECK(redacted.find("secret") == std::string::npos);
  auto store = CreatePlatformSecretStore();
  const auto protectedValue = store->Protect("sensitive-value");
  CHECK(protectedValue.find("sensitive-value") == std::string::npos);
  CHECK(store->Unprotect(protectedValue) == "sensitive-value");
  const auto sessionValue = store->ProtectSession("session-sensitive");
  CHECK(sessionValue.find("session-sensitive") == std::string::npos);
  CHECK(store->Unprotect(sessionValue) == "session-sensitive");

  const auto root = std::filesystem::temp_directory_path() / ("ai-usage-secret-test-" + std::to_string(Clock::now().time_since_epoch().count()));
  std::filesystem::create_directories(root);
  const DataPaths paths{root, root / "settings.json", root / "cache.json", true};
  Settings settings;
  ProviderConfig provider{"secret", "Secret", ProviderKind::DeepSeek, false};
  provider.encryptedApiKey = protectedValue;
  settings.providers.push_back(provider);
  SaveSettings(paths, settings);
  std::ifstream saved(paths.settings, std::ios::binary);
  const std::string disk((std::istreambuf_iterator<char>(saved)), std::istreambuf_iterator<char>());
  CHECK(disk.find("sensitive-value") == std::string::npos);
  std::error_code cleanup;
  std::filesystem::remove_all(root, cleanup);
}

void TestProcessCancellationAndSingleInstance() {
  auto runner = CreatePlatformProcessRunner();
  ProcessRequest request;
#ifdef _WIN32
  request.executable = DiscoverExecutable("cmd").value();
  request.arguments = {"/d", "/c", "ping -n 20 127.0.0.1 >nul"};
#else
  request.executable = "/bin/sh";
  request.arguments = {"-c", "sleep 10"};
#endif
  request.timeout = std::chrono::seconds{5};
  std::atomic<bool> cancel{false};
  request.cancellationRequested = [&] { return cancel.load(); };
  std::jthread canceller([&] {
    std::this_thread::sleep_for(std::chrono::milliseconds{100});
    cancel = true;
  });
  const auto started = std::chrono::steady_clock::now();
  const auto result = runner->Run(request);
  CHECK(result.cancelled);
  CHECK(std::chrono::steady_clock::now() - started < std::chrono::seconds{3});

  const auto root = std::filesystem::temp_directory_path() /
                    ("ai-usage-instance-test-" + std::to_string(Clock::now().time_since_epoch().count()));
  auto primary = CreatePlatformSingleInstanceSignal(root);
  auto secondary = CreatePlatformSingleInstanceSignal(root);
  CHECK(!primary->IsAnotherRunning());
  CHECK(secondary->IsAnotherRunning());
  secondary->SignalActivation();
  CHECK(primary->ConsumeActivation());
  CHECK(!primary->ConsumeActivation());
  std::error_code cleanup;
  std::filesystem::remove_all(root, cleanup);
}

void TestProviderEndToEnd() {
  FakeHttp http;
  FakeProcess process;
  FakeSecrets secrets;
  ProviderConfig config{"deepseek", "DeepSeek", ProviderKind::DeepSeek, true};
  config.baseUrl = "https://api.deepseek.com";
  config.balancePath = "/user/balance";
  config.encryptedApiKey = "protected:test-key";
  http.response = {200, {}, ReadFixture("deepseek_balance.json")};
  auto provider = CreateProvider(config, http, process, secrets);
  const auto snapshot = provider->Refresh();
  CHECK(snapshot.health == Health::Healthy);
  CHECK(http.last.headers.at("Authorization") == "Bearer test-key");

  http.response = {429, {{"Retry-After", "120"}}, {}};
  bool rateLimited = false;
  try {
    (void)provider->Refresh();
  } catch (const ProviderException& error) {
    rateLimited = true;
    CHECK(error.Error().code == "rate-limited");
    CHECK(error.Error().retryAfter == std::chrono::seconds{120});
  }
  CHECK(rateLimited);

  FakeProcess codexProcess;
  codexProcess.result = {0, ReadFixture("codex_multi_window.jsonl"), {}, false};
  ProviderConfig codexConfig{"codex", "Codex", ProviderKind::Codex, true};
  codexConfig.executable = "codex";
  auto codex = CreateProvider(codexConfig, http, codexProcess, secrets);
  CHECK(codex->Refresh().health == Health::Healthy);
  CHECK(codexProcess.last.standardInput.find("account/rateLimits/read") != std::string::npos);
  CHECK(codexProcess.last.standardInputCloseDelay == std::chrono::milliseconds{3000});
  codexProcess.result.standardOutput = ReadFixture("codex_unauthorized.jsonl");
  const auto unauthorized = codex->Refresh();
  CHECK(unauthorized.health == Health::Error);
  CHECK(unauthorized.error.has_value() && unauthorized.error->code == "unauthorized");

  FakeHttp genericHttp;
  genericHttp.response = {200, {}, ReadFixture("generic_usage.json")};
  ProviderConfig genericConfig{"generic", "Generic", ProviderKind::OpenAiCompatible, true};
  genericConfig.baseUrl = "https://example.test";
  genericConfig.usagePath = "/usage";
  genericConfig.jsonPointers = {{"total_tokens", "/usage/total_tokens"}};
  auto generic = CreateProvider(genericConfig, genericHttp, process, secrets);
  CHECK(generic->Refresh().health == Health::Healthy);
  genericHttp.response.body = R"({"usage":{"renamed_total":33}})";
  bool schemaChangeRejected = false;
  try { (void)generic->Refresh(); } catch (...) { schemaChangeRejected = true; }
  CHECK(schemaChangeRejected);

  FakeProcess claudeProcess;
  claudeProcess.result = ProcessResult{1, {}, "not logged in", false};
  ProviderConfig claudeConfig{"claude", "Claude", ProviderKind::ClaudeSubscription, true};
  claudeConfig.executable = "claude";
  auto claude = CreateProvider(claudeConfig, http, claudeProcess, secrets);
  bool claudeRejected = false;
  try { (void)claude->Refresh(); } catch (...) { claudeRejected = true; }
  CHECK(claudeRejected);
}

void TestOllamaProvider() {
  FakeHttp http;
  FakeProcess process;
  FakeSecrets secrets;
  ProviderConfig config{"ollama", "Ollama", ProviderKind::Ollama, true};
  config.baseUrl = "http://localhost:11434";
  config.allowLoopbackHttp = true;
  http.response = {200, {}, ReadFixture("ollama_idle.json")};
  auto provider = CreateProvider(config, http, process, secrets);
  const auto idle = provider->Refresh();
  CHECK(idle.health == Health::Healthy);
  CHECK(http.last.method == "GET");
  CHECK(http.last.url == "http://localhost:11434/api/ps");
  CHECK(http.last.allowLoopbackHttp);
  CHECK(http.last.headers.find("Authorization") == http.last.headers.end());
  CHECK(idle.metrics.size() == 1U);
  CHECK(idle.metrics[0].value == "0");
  CHECK(idle.metrics[0].kind == MetricKind::LoadedModels);

  http.response = {200, {}, ReadFixture("ollama_loaded.json")};
  const auto loaded = provider->Refresh();
  CHECK(loaded.health == Health::Healthy);
  CHECK(loaded.metrics.size() == 2U);
  CHECK(loaded.metrics[0].value == "1");

  ProviderConfig protectedConfig = config;
  protectedConfig.encryptedApiKey = "protected:ollama-secret";
  auto protectedProvider = CreateProvider(protectedConfig, http, process, secrets);
  http.response = {200, {}, ReadFixture("ollama_idle.json")};
  CHECK(protectedProvider->Refresh().health == Health::Healthy);
  CHECK(http.last.headers.at("Authorization") == "Bearer ollama-secret");

  for (const int status : {401, 403}) {
    http.response = {status, {}, {}};
    bool rejected = false;
    try { (void)protectedProvider->Refresh(); }
    catch (const ProviderException& error) {
      rejected = true;
      CHECK(error.Error().code == "unauthorized");
      CHECK(error.Error().message.find("ollama-secret") == std::string::npos);
    }
    CHECK(rejected);
  }

  http.response = {200, {}, R"({"models":{}})"};
  bool malformedRejected = false;
  try { (void)protectedProvider->Refresh(); } catch (...) { malformedRejected = true; }
  CHECK(malformedRejected);

  http.response = {200, {}, ReadFixture("ollama_idle.json")};
  const auto test = protectedProvider->TestConnection();
  CHECK(test.success);
  CHECK(!test.capabilities.usage);
  CHECK(!test.capabilities.remaining);
  CHECK(!test.capabilities.balance);
  CHECK(!test.capabilities.tokenActivity);
}

void TestTooltip() {
  const auto now = Clock::now();
  ProviderSnapshot snapshot{"codex", "Codex", ProviderKind::Codex, now - std::chrono::minutes{3}, Freshness::Fresh, Health::Healthy};
  snapshot.metrics.push_back(Metric{MetricKind::UsedPercent, "25", MetricUnit::Percent, MetricScope::RollingWindow});
  snapshot.metrics.push_back(Metric{MetricKind::RemainingPercent, "75", MetricUnit::Percent, MetricScope::RollingWindow});
  const auto tooltip = ComposeTooltip({snapshot}, now, 30);
  CHECK(tooltip.size() <= 30U);
  CHECK(tooltip.find("Codex") != std::string::npos);
  CHECK(tooltip.find("25%") != std::string::npos);
  CHECK(tooltip.find("75%") == std::string::npos);
  CHECK(tooltip.find("3m") != std::string::npos);
  CHECK(tooltip.starts_with("IA: healthy"));
  ProviderSnapshot disabled{"disabled", "Disabled", ProviderKind::OpenAiCompatible, now,
                            Freshness::NoData, Health::Disabled};
  const auto disabledTooltip = ComposeTooltip({disabled}, now, 127);
  CHECK(disabledTooltip == "IA: disabled");
  ProviderSnapshot error{"broken", "A Error", ProviderKind::ClaudeSubscription, now, Freshness::NoData, Health::Error};
  error.error = ProviderError{"unauthorized", "denied", false, std::nullopt};
  const auto prioritized = ComposeTooltip({snapshot, error}, now, 127);
  CHECK(prioritized.size() <= 127U);
  CHECK(prioritized.starts_with("IA: error"));
  CHECK(prioritized.find("A Error") < prioritized.find("Codex"));

  ProviderSnapshot ollama{"ollama", "Ollama", ProviderKind::Ollama, now, Freshness::Fresh, Health::Healthy};
  Metric loadedModels{MetricKind::LoadedModels, "2", MetricUnit::Count, MetricScope::CurrentObservation};
  loadedModels.label = "Modelos cargados";
  Metric modelMemory{MetricKind::ResourceMemory, "1234567890", MetricUnit::Bytes,
                     MetricScope::CurrentObservation};
  modelMemory.label = "llama3.1:latest";
  ollama.metrics.push_back(loadedModels);
  ollama.metrics.push_back(modelMemory);
  const auto ollamaTooltip = ComposeTooltip({ollama}, now, 127);
  CHECK(ollamaTooltip.find("2 modelos") != std::string::npos);
  CHECK(ollamaTooltip.find("1234567890") == std::string::npos);
}

void TestPresentationRules() {
  Metric count{MetricKind::LoadedModels, "2", MetricUnit::Count, MetricScope::CurrentObservation};
  count.label = "Modelos cargados";
  Metric singleCount{MetricKind::LoadedModels, "1", MetricUnit::Count, MetricScope::CurrentObservation};
  Metric memory{MetricKind::ResourceMemory, "1234", MetricUnit::Bytes, MetricScope::CurrentObservation};
  CHECK(FormatMetric(count) == "2 modelos");
  CHECK(FormatMetric(singleCount) == "1 modelo");
  CHECK(FormatMetric(memory) == "1234 bytes");

  const PresentationRgb white{255, 255, 255};
  const PresentationRgb dark{24, 32, 48};
  const PresentationRgb muted{150, 150, 150};
  CHECK(ContrastRatio(white, dark) >= 4.5);
  CHECK(ContrastRatio(muted, white) < 4.5);
  const auto corrected = EnsureTextContrast(muted, white);
  CHECK(ContrastRatio(corrected, white) >= 4.5);
  CHECK(!UseCompactLayout(800));
  CHECK(UseCompactLayout(460));
  CHECK(UseCompactLayout(639));
  CHECK(!UseCompactLayout(640));
  CHECK(ScaleForDpi(440, 100) == 440);
  CHECK(ScaleForDpi(440, 125) == 550);
  CHECK(ScaleForDpi(440, 150) == 660);
  CHECK(ScaleForDpi(440, 200) == 880);
  CHECK(ScaleForDpi(0, 200) == 0);
}

void TestSchedulerConcurrencyAndCoalescing() {
  RefreshTracker parallel;
  std::mutex deliveredMutex;
  std::condition_variable deliveredCondition;
  int delivered = 0;
  RefreshScheduler scheduler([&](const ProviderSnapshot&) {
    std::lock_guard lock(deliveredMutex);
    ++delivered;
    deliveredCondition.notify_all();
  });
  std::vector<std::unique_ptr<IUsageProvider>> providers;
  providers.push_back(std::make_unique<TrackedProvider>("one", parallel, std::chrono::milliseconds{120}));
  providers.push_back(std::make_unique<TrackedProvider>("two", parallel, std::chrono::milliseconds{120}));
  scheduler.SetProviders(std::move(providers));
  scheduler.Start();
  {
    std::unique_lock lock(deliveredMutex);
    CHECK(deliveredCondition.wait_for(lock, std::chrono::seconds{3}, [&] { return delivered >= 2; }));
  }
  scheduler.Stop();
  CHECK(parallel.maximum == 2);
  CHECK(parallel.calls == 2);

  RefreshTracker coalesced;
  delivered = 0;
  RefreshScheduler one([&](const ProviderSnapshot&) {
    std::lock_guard lock(deliveredMutex);
    ++delivered;
    deliveredCondition.notify_all();
  });
  std::vector<std::unique_ptr<IUsageProvider>> single;
  single.push_back(std::make_unique<TrackedProvider>("single", coalesced, std::chrono::milliseconds{180}));
  one.SetProviders(std::move(single));
  one.Start();
  for (int count = 0; count < 100 && coalesced.active == 0; ++count) std::this_thread::sleep_for(std::chrono::milliseconds{5});
  CHECK(coalesced.active == 1);
  for (int count = 0; count < 10; ++count) one.RefreshOne("single");
  {
    std::unique_lock lock(deliveredMutex);
    CHECK(deliveredCondition.wait_for(lock, std::chrono::seconds{3}, [&] { return delivered >= 2; }));
  }
  std::this_thread::sleep_for(std::chrono::milliseconds{250});
  one.Stop();
  CHECK(coalesced.calls == 2);
}

void TestSchedulerFakeClockCadence() {
  RefreshTracker tracker;
  std::mutex deliveredMutex;
  std::condition_variable deliveredCondition;
  int delivered = 0;
  auto clock = std::make_unique<FakeClock>(Clock::now());
  auto* fakeClock = clock.get();
  RefreshScheduler scheduler([&](const ProviderSnapshot&) {
    std::lock_guard lock(deliveredMutex);
    ++delivered;
    deliveredCondition.notify_all();
  }, std::move(clock));
  std::vector<std::unique_ptr<IUsageProvider>> providers;
  providers.push_back(std::make_unique<TrackedProvider>("cadence", tracker, std::chrono::milliseconds{0}));
  scheduler.SetProviders(std::move(providers));
  scheduler.SetInterval(std::chrono::minutes{5});
  scheduler.Start();
  {
    std::unique_lock lock(deliveredMutex);
    CHECK(deliveredCondition.wait_for(lock, std::chrono::seconds{2}, [&] { return delivered >= 1; }));
  }
  CHECK(tracker.calls == 1);
  fakeClock->Advance(std::chrono::minutes{5});
  scheduler.NotifyClockChanged();
  {
    std::unique_lock lock(deliveredMutex);
    CHECK(deliveredCondition.wait_for(lock, std::chrono::seconds{2}, [&] { return delivered >= 2; }));
  }
  scheduler.Stop();
  CHECK(tracker.calls == 2);
}

void TestSchedulerFakeClockFailures() {
  const auto runScenario = [](ProviderError error, std::chrono::seconds beforeDue, std::chrono::seconds atDue) {
    std::atomic<int> calls{0};
    std::mutex deliveredMutex;
    std::condition_variable deliveredCondition;
    int delivered = 0;
    auto clock = std::make_unique<FakeClock>(Clock::now());
    auto* fakeClock = clock.get();
    RefreshScheduler scheduler([&](const ProviderSnapshot& snapshot) {
      CHECK(snapshot.health == Health::Error);
      std::lock_guard lock(deliveredMutex);
      ++delivered;
      deliveredCondition.notify_all();
    }, std::move(clock));
    std::vector<std::unique_ptr<IUsageProvider>> providers;
    providers.push_back(std::make_unique<FailingProvider>("failure", std::move(error), calls));
    scheduler.SetProviders(std::move(providers));
    scheduler.Start();
    {
      std::unique_lock lock(deliveredMutex);
      CHECK(deliveredCondition.wait_for(lock, std::chrono::seconds{2}, [&] { return delivered >= 1; }));
    }
    fakeClock->Advance(beforeDue);
    scheduler.NotifyClockChanged();
    std::this_thread::sleep_for(std::chrono::milliseconds{75});
    CHECK(calls == 1);
    fakeClock->Advance(atDue);
    scheduler.NotifyClockChanged();
    {
      std::unique_lock lock(deliveredMutex);
      CHECK(deliveredCondition.wait_for(lock, std::chrono::seconds{2}, [&] { return delivered >= 2; }));
    }
    scheduler.Stop();
    CHECK(calls == 2);
  };

  runScenario(ProviderError{"timeout", "timed out", true, std::nullopt}, std::chrono::seconds{29},
              std::chrono::seconds{31});
  runScenario(ProviderError{"rate-limited", "wait", true, std::chrono::seconds{120}},
              std::chrono::seconds{119}, std::chrono::seconds{1});

  std::atomic<int> manualCalls{0};
  std::mutex manualMutex;
  std::condition_variable manualCondition;
  int manualDelivered = 0;
  auto manualClock = std::make_unique<FakeClock>(Clock::now());
  RefreshScheduler manual([&](const ProviderSnapshot&) {
    std::lock_guard lock(manualMutex);
    ++manualDelivered;
    manualCondition.notify_all();
  }, std::move(manualClock));
  std::vector<std::unique_ptr<IUsageProvider>> manualProviders;
  manualProviders.push_back(std::make_unique<FailingProvider>(
      "manual", ProviderError{"rate-limited", "wait", true, std::chrono::seconds{120}}, manualCalls));
  manual.SetProviders(std::move(manualProviders));
  manual.Start();
  {
    std::unique_lock lock(manualMutex);
    CHECK(manualCondition.wait_for(lock, std::chrono::seconds{2}, [&] { return manualDelivered >= 1; }));
  }
  manual.RefreshOne("manual");
  {
    std::unique_lock lock(manualMutex);
    CHECK(manualCondition.wait_for(lock, std::chrono::seconds{2}, [&] { return manualDelivered >= 2; }));
  }
  manual.Stop();
  CHECK(manualCalls == 2);
}

}  // namespace

int main(int argc, char** argv) {
  if (argc == 2 && std::string(argv[1]) == "--probe-codex-usage") {
    const auto executable = DiscoverExecutable("codex");
    if (!executable.has_value()) {
      std::cerr << "Codex executable not found\n";
      return 2;
    }
    const std::string requests =
        "{\"method\":\"initialize\",\"id\":1,\"params\":{\"clientInfo\":{\"name\":\"ai-usage-monitor\",\"title\":\"AI Usage Monitor\",\"version\":\"0.1.1\"},\"capabilities\":{}}}\n"
        "{\"method\":\"initialized\",\"params\":{}}\n"
        "{\"method\":\"account/read\",\"id\":2,\"params\":{\"refreshToken\":false}}\n"
        "{\"method\":\"account/rateLimits/read\",\"id\":3}\n"
        "{\"method\":\"account/usage/read\",\"id\":4}\n";
    auto runner = CreatePlatformProcessRunner();
    const auto result = runner->Run(ProcessRequest{*executable, {"app-server", "--listen", "stdio://"}, requests,
                                                    std::chrono::milliseconds{10000}, {},
                                                    std::chrono::milliseconds{3000}});
    std::cout << "exit=" << result.exitCode << " timeout=" << (result.timedOut ? "yes" : "no")
              << " stdout-bytes=" << result.standardOutput.size() << " stderr-bytes=" << result.standardError.size();
    ProviderConfig config{"codex-probe", "Codex", ProviderKind::Codex, true};
    config.executable = *executable;
    try {
      const auto parsed = ParseCodexResponses(config, result.standardOutput, Clock::now());
      std::cout << " metrics=" << parsed.metrics.size() << '\n';
      return !result.timedOut && !parsed.metrics.empty() ? 0 : 3;
    } catch (const std::exception& error) {
      std::cout << " parse-error=" << error.what() << '\n';
      return 3;
    }
  }
  if (argc == 2 && std::string(argv[1]) == "--probe-claude-usage") {
    const auto executable = DiscoverExecutable("claude");
    if (!executable.has_value()) {
      std::cerr << "Claude executable not found\n";
      return 2;
    }
    auto runner = CreatePlatformProcessRunner();
    ProviderConfig config{"claude-probe", "Claude", ProviderKind::ClaudeSubscription, true};
    config.executable = *executable;
    const auto result = runner->Run(ProcessRequest{*executable, {"/usage"}, {}, std::chrono::milliseconds{10000}});
    const auto parsed = ParseClaudeUsageText(config, result.standardOutput, Clock::now());
    std::cout << "usage-compatible=" << (parsed.has_value() ? "yes" : "no") << '\n';
    return parsed.has_value() ? 0 : 3;
  }
  struct TestCase {
    const char* name;
    const char* suite;
    std::function<void()> run;
  };
  const std::vector<TestCase> tests{
      {"domain", "unit", TestDomainValidation}, {"aggregate", "unit", TestAggregate},
      {"codex", "fixture", TestCodexParser}, {"deepseek", "fixture", TestDeepSeekParser},
      {"claude", "fixture", TestClaudeParser}, {"claude-bridge", "fixture", TestClaudeBridge},
      {"generic", "fixture", TestGenericParser}, {"ollama", "fixture", TestOllamaParser},
      {"ollama-provider", "fixture", TestOllamaProvider}, {"settings", "unit", TestSettingsAndCache},
      {"ollama-settings", "unit", TestOllamaSettingsAndCache},
      {"security", "unit", TestSecurityHelpers},
      {"process-instance", "unit", TestProcessCancellationAndSingleInstance},
      {"provider", "fixture", TestProviderEndToEnd},
      {"tooltip", "unit", TestTooltip},
      {"overlay", "unit", TestOverlayPresentationModel},
      {"presentation", "unit", TestPresentationRules},
      {"scheduler", "unit", TestSchedulerConcurrencyAndCoalescing},
      {"scheduler-clock", "unit", TestSchedulerFakeClockCadence},
      {"scheduler-failures", "unit", TestSchedulerFakeClockFailures}};
  int executed = 0;
  for (const auto& [name, suite, test] : tests) {
    if (std::string_view(suite) != AI_USAGE_TEST_SUITE) continue;
    ++executed;
    try { test(); }
    catch (const std::exception& error) { std::cerr << name << " threw: " << error.what() << '\n'; ++failures; }
  }
  if (failures == 0) std::cout << executed << ' ' << AI_USAGE_TEST_SUITE << " tests passed\n";
  return failures == 0 ? 0 : 1;
}
