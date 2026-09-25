#include "ai_usage/console/console_dashboard.h"

#include "ai_usage/config.h"
#include "ai_usage/overlay.h"
#include "ai_usage/platform.h"
#include "ai_usage/presentation.h"
#include "ai_usage/providers.h"
#include "ai_usage/scheduler.h"
#include "ai_usage/tooltip.h"

#include <nlohmann/json.hpp>

#include <poll.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <csignal>
#include <cstdio>
#include <ctime>
#include <fstream>
#include <iostream>
#include <map>
#include <mutex>
#include <sstream>
#include <string_view>

namespace ai_usage::console {
namespace {

constexpr int kDefaultWidth = 100;
constexpr int kMinBoxWidth = 44;
constexpr int kMaxBoxWidth = 112;
constexpr std::chrono::milliseconds kInputPollTimeout{200};
constexpr std::chrono::seconds kRedrawInterval{1};

std::atomic<bool> gQuitRequested{false};

void HandleTerminationSignal(int) { gQuitRequested.store(true); }

int TerminalWidth() {
  struct winsize size {};
  if (ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0 && size.ws_col > 0) {
    return size.ws_col;
  }
  return kDefaultWidth;
}

// ANSI SGR codes. Kept as plain escape sequences (no external TUI dependency,
// consistent with the project's hand-rolled presentation helpers).
constexpr const char* kReset = "\x1b[0m";
constexpr const char* kBold = "\x1b[1m";
constexpr const char* kDim = "\x1b[2m";
constexpr const char* kFgGreen = "\x1b[32m";
constexpr const char* kFgYellow = "\x1b[33m";
constexpr const char* kFgRed = "\x1b[31m";
constexpr const char* kFgCyan = "\x1b[36m";
constexpr const char* kFgBlue = "\x1b[34m";
constexpr const char* kFgGray = "\x1b[90m";
constexpr const char* kFgWhite = "\x1b[97m";

constexpr const char* kBoxHorizontal = "─";  // ─
constexpr const char* kBoxVertical = "│";    // │
constexpr const char* kBoxTopLeft = "╭";     // ╭
constexpr const char* kBoxTopRight = "╮";    // ╮
constexpr const char* kBoxBottomLeft = "╰";  // ╰
constexpr const char* kBoxBottomRight = "╯"; // ╯
constexpr const char* kBlockFull = "█";      // █
constexpr const char* kBlockEmpty = "░";     // ░
constexpr const char* kDot = "●";            // ●

std::string RepeatUtf8(const char* symbol, int count) {
  std::string result;
  if (count <= 0) return result;
  result.reserve(static_cast<std::size_t>(count) * std::char_traits<char>::length(symbol));
  for (int i = 0; i < count; ++i) result += symbol;
  return result;
}

// Counts display columns, skipping ANSI SGR escapes and UTF-8 continuation
// bytes, so box borders line up even though colored/multi-byte text is not
// the same byte length as its on-screen width (assumes single-width glyphs,
// true for the box/block/dot characters and Latin text used here).
std::size_t VisibleLength(const std::string& text) {
  std::size_t length = 0;
  for (std::size_t i = 0; i < text.size();) {
    if (text[i] == '\x1b') {
      const auto end = text.find('m', i);
      i = (end == std::string::npos) ? text.size() : end + 1;
      continue;
    }
    const auto byte = static_cast<unsigned char>(text[i]);
    if ((byte & 0xC0) != 0x80) ++length;
    ++i;
  }
  return length;
}

int BoxWidthFor(int terminalWidth) { return std::clamp(terminalWidth - 2, kMinBoxWidth, kMaxBoxWidth); }

std::string PadToWidth(const std::string& content, std::size_t innerWidth) {
  const auto visible = VisibleLength(content);
  if (visible >= innerWidth) return content;
  return content + std::string(innerWidth - visible, ' ');
}

std::string BoxTop(const std::string& coloredTitle, int boxWidth) {
  std::ostringstream out;
  out << kFgBlue << kBoxTopLeft << kBoxHorizontal << kReset << ' ' << coloredTitle << kReset << ' ' << kFgBlue;
  const auto used = 2 + 1 + VisibleLength(coloredTitle) + 1 + 1;  // corner+dash, space, title, space, corner
  const int remaining = std::max(0, boxWidth - static_cast<int>(used));
  out << RepeatUtf8(kBoxHorizontal, remaining) << kBoxTopRight << kReset;
  return out.str();
}

std::string BoxBottom(int boxWidth) {
  std::ostringstream out;
  out << kFgBlue << kBoxBottomLeft << RepeatUtf8(kBoxHorizontal, std::max(0, boxWidth - 2)) << kBoxBottomRight
      << kReset;
  return out.str();
}

std::string BoxLine(const std::string& content, int boxWidth) {
  const std::size_t innerWidth = static_cast<std::size_t>(std::max(0, boxWidth - 4));
  std::ostringstream out;
  out << kFgBlue << kBoxVertical << kReset << ' ' << PadToWidth(content, innerWidth) << ' ' << kFgBlue
      << kBoxVertical << kReset;
  return out.str();
}

std::string ObservationLabel(const ProviderSnapshot& snapshot, TimePoint now) {
  if (snapshot.observedAt == TimePoint{}) return "Sin actualización";
  const auto raw = Clock::to_time_t(snapshot.observedAt);
  std::tm parts{};
  localtime_r(&raw, &parts);
  std::ostringstream stamp;
  stamp << std::put_time(&parts, "%Y-%m-%d %H:%M:%S");
  std::string freshness;
  switch (snapshot.freshness) {
    case Freshness::Fresh: freshness = "Datos actuales"; break;
    case Freshness::Stale: freshness = "Datos anteriores"; break;
    case Freshness::NoData: freshness = "Sin datos"; break;
  }
  (void)now;
  return stamp.str() + "  ·  " + freshness;
}

const char* HealthColor(Health health) {
  switch (health) {
    case Health::Healthy: return kFgGreen;
    case Health::Partial: return kFgYellow;
    case Health::Error: return kFgRed;
    case Health::Disabled: return kFgGray;
  }
  return kFgGray;
}

std::string HealthLabel(Health health) {
  std::string text;
  switch (health) {
    case Health::Healthy: text = "Conectado"; break;
    case Health::Partial: text = "Información parcial"; break;
    case Health::Error: text = "Error"; break;
    case Health::Disabled: text = "Deshabilitado"; break;
    default: text = "Desconocido"; break;
  }
  const char* color = HealthColor(health);
  return std::string(color) + kDot + kReset + ' ' + color + text + kReset;
}

const char* PercentColor(int percent) {
  if (percent >= 90) return kFgRed;
  if (percent >= 70) return kFgYellow;
  return kFgGreen;
}

std::string ProvenanceLabel(Provenance provenance) {
  switch (provenance) {
    case Provenance::ProviderReported: return "Reportado por el proveedor";
    case Provenance::CliBridge: return "Obtenido del CLI local";
    case Provenance::LocallyObserved: return "Observado localmente";
    case Provenance::Derived: return "Calculado localmente";
  }
  return "Origen desconocido";
}

std::string MetricLabel(const Metric& metric) {
  return metric.label.empty() ? ToString(metric.kind) : metric.label;
}

int PercentValue(const Metric& metric) {
  try {
    const auto value = std::stod(metric.value);
    if (!std::isfinite(value)) return 0;
    return std::clamp(static_cast<int>(std::lround(value)), 0, 100);
  } catch (...) {
    return 0;
  }
}

std::string MetricMetadata(const Metric& metric, TimePoint now) {
  auto metadata = FormatResetMetadata(metric, now);
  if (metric.provenance != Provenance::ProviderReported) {
    if (!metadata.empty()) metadata += "  ·  ";
    metadata += ProvenanceLabel(metric.provenance);
  }
  return metadata;
}

bool VisibleMetric(const Metric& metric) {
  return metric.kind != MetricKind::RemainingPercent && metric.kind != MetricKind::ResourceMemory &&
         metric.kind != MetricKind::Requests;
}

}  // namespace

namespace {

using Json = nlohmann::json;

std::string ToIso8601Utc(TimePoint value) {
  const auto raw = Clock::to_time_t(value);
  std::tm parts{};
  gmtime_r(&raw, &parts);
  std::ostringstream out;
  out << std::put_time(&parts, "%Y-%m-%dT%H:%M:%SZ");
  return out.str();
}

Json MetricToJson(const Metric& metric) {
  Json result{{"kind", ToString(metric.kind)},   {"label", MetricLabel(metric)},
              {"value", metric.value},           {"unit", ToString(metric.unit)},
              {"scope", ToString(metric.scope)}, {"provenance", ToString(metric.provenance)},
              {"availability", ToString(metric.availability)}};
  if (metric.resetsAt.has_value()) result["resetsAt"] = ToIso8601Utc(*metric.resetsAt);
  if (metric.window.has_value()) result["windowSeconds"] = metric.window->count();
  return result;
}

Json SnapshotToJson(const ProviderSnapshot& snapshot) {
  Json metrics = Json::array();
  for (const auto& metric : snapshot.metrics) metrics.push_back(MetricToJson(metric));
  Json result{{"providerId", snapshot.providerId},
              {"displayName", snapshot.displayName},
              {"kind", ToString(snapshot.kind)},
              {"health", ToString(snapshot.health)},
              {"freshness", ToString(snapshot.freshness)},
              {"observedAt", snapshot.observedAt == TimePoint{} ? Json(nullptr) : Json(ToIso8601Utc(snapshot.observedAt))},
              {"accountLabel", snapshot.accountLabel},
              {"metrics", metrics}};
  if (snapshot.error.has_value()) {
    result["error"] = Json{{"code", snapshot.error->code}, {"message", snapshot.error->message},
                           {"retryable", snapshot.error->transient}};
  } else {
    result["error"] = nullptr;
  }
  return result;
}

}  // namespace

std::string SnapshotsToJson(const std::vector<ProviderSnapshot>& snapshots) {
  Json array = Json::array();
  for (const auto& snapshot : snapshots) array.push_back(SnapshotToJson(snapshot));
  return array.dump();
}

std::string RenderProgressBar(int usedPercent, int width) {
  const int clampedPercent = std::clamp(usedPercent, 0, 100);
  const int clampedWidth = std::max(width, 4);
  const int filled = std::clamp(static_cast<int>(std::lround(clampedWidth * clampedPercent / 100.0)), 0,
                                clampedWidth);
  const char* color = PercentColor(clampedPercent);
  std::ostringstream bar;
  bar << kFgGray << '[' << kReset << color << RepeatUtf8(kBlockFull, filled) << kReset << kFgGray
      << RepeatUtf8(kBlockEmpty, clampedWidth - filled) << kReset << kFgGray << ']' << kReset << ' ' << color
      << std::to_string(clampedPercent) << '%' << kReset;
  return bar.str();
}

std::string RenderProviderSection(const ProviderSnapshot& snapshot, TimePoint now, int boxWidth) {
  std::ostringstream out;
  out << BoxTop(std::string(kBold) + kFgCyan + snapshot.displayName + kReset + "  " + HealthLabel(snapshot.health),
              boxWidth)
      << "\n";
  out << BoxLine(std::string(kDim) + ObservationLabel(snapshot, now) + kReset, boxWidth) << "\n";
  if (!snapshot.accountLabel.empty()) {
    out << BoxLine(std::string(kDim) + "Cuenta · " + kReset + snapshot.accountLabel, boxWidth) << "\n";
  }

  const bool anyVisible = std::any_of(snapshot.metrics.begin(), snapshot.metrics.end(), VisibleMetric);
  if (!anyVisible) {
    out << BoxLine(std::string(kFgGray) + "— Métricas no disponibles" + kReset, boxWidth) << "\n";
  }

  for (const auto& metric : snapshot.metrics) {
    if (!VisibleMetric(metric)) continue;
    out << BoxLine(std::string(kFgWhite) + MetricLabel(metric) + kReset + ": " + kBold + FormatMetric(metric) +
                     kReset,
                 boxWidth)
        << "\n";
    if (metric.availability == Availability::Available && metric.unit == MetricUnit::Percent) {
      out << BoxLine("  " + RenderProgressBar(PercentValue(metric), 26), boxWidth) << "\n";
    }
    const auto metadata = MetricMetadata(metric, now);
    if (!metadata.empty()) out << BoxLine(std::string(kDim) + "  " + metadata + kReset, boxWidth) << "\n";
  }

  if (snapshot.error.has_value()) {
    const auto& error = *snapshot.error;
    const bool refreshing = error.code == "refreshing";
    const char* color = refreshing ? kFgCyan : kFgRed;
    const std::string prefix = refreshing ? "↻ " : "Atención · ";
    out << BoxLine(std::string(color) + prefix + error.message + kReset, boxWidth) << "\n";
  }

  out << BoxBottom(boxWidth);
  return out.str();
}

std::string RenderDashboard(const std::vector<ProviderSnapshot>& snapshots, TimePoint now, int width) {
  const int boxWidth = BoxWidthFor(width);
  std::ostringstream out;
  out << "\x1b[2J\x1b[H";
  const auto raw = Clock::to_time_t(now);
  std::tm parts{};
  localtime_r(&raw, &parts);
  std::ostringstream stamp;
  stamp << std::put_time(&parts, "%Y-%m-%d %H:%M:%S");
  out << kBold << kFgCyan << "AI Usage Monitor" << kReset << kDim << "  ·  Consola  ·  " << stamp.str() << kReset
      << "\n\n";
  for (const auto& snapshot : snapshots) out << RenderProviderSection(snapshot, now, boxWidth) << "\n\n";
  out << kDim << RepeatUtf8(kBoxHorizontal, std::max(boxWidth, 20)) << kReset << "\n";
  out << kBold << "[r]" << kReset << " Refrescar todo    " << kBold << "[q]" << kReset << " Salir\n";
  return out.str();
}

namespace {

class RawTerminalMode {
 public:
  RawTerminalMode() {
    if (tcgetattr(STDIN_FILENO, &original_) != 0) return;
    valid_ = true;
    struct termios raw = original_;
    raw.c_lflag &= static_cast<unsigned int>(~(ICANON | ECHO));
    raw.c_cc[VMIN] = 0;
    raw.c_cc[VTIME] = 0;
    tcsetattr(STDIN_FILENO, TCSANOW, &raw);
  }
  ~RawTerminalMode() {
    if (valid_) tcsetattr(STDIN_FILENO, TCSANOW, &original_);
  }
  RawTerminalMode(const RawTerminalMode&) = delete;
  RawTerminalMode& operator=(const RawTerminalMode&) = delete;

 private:
  struct termios original_ {};
  bool valid_{false};
};

std::optional<char> PollKeyPress(std::chrono::milliseconds timeout) {
  struct pollfd fd {
    STDIN_FILENO, POLLIN, 0
  };
  const int result = poll(&fd, 1, static_cast<int>(timeout.count()));
  if (result <= 0 || (fd.revents & POLLIN) == 0) return std::nullopt;
  char key = 0;
  if (read(STDIN_FILENO, &key, 1) != 1) return std::nullopt;
  return key;
}

std::optional<std::string> DefaultExecutableCommand(ProviderKind kind) {
  if (kind == ProviderKind::Codex) return "codex";
  if (kind == ProviderKind::ClaudeSubscription) return "claude";
  return std::nullopt;
}

std::vector<std::unique_ptr<IUsageProvider>> BuildProviders(const Settings& settings, IHttpClient& http,
                                                            IProcessRunner& process, ISecretStore& secrets) {
  std::vector<std::unique_ptr<IUsageProvider>> providers;
  for (const auto& config : settings.providers) {
    if (!config.enabled) continue;
    auto runtimeConfig = config;
    if (const auto command = DefaultExecutableCommand(config.kind); command.has_value()) {
      if (runtimeConfig.executable.empty()) runtimeConfig.executable = *command;
      if (!runtimeConfig.executable.has_parent_path()) {
        if (const auto found = DiscoverExecutable(runtimeConfig.executable.string()); found.has_value()) {
          runtimeConfig.executable = *found;
        }
      }
    }
    providers.push_back(CreateProvider(runtimeConfig, http, process, secrets));
  }
  return providers;
}

enum class OutputFormat { Text, Json };

struct CliOptions {
  bool once{false};
  OutputFormat format{OutputFormat::Text};
  bool invalidFormat{false};
  std::string invalidFormatValue;
};

CliOptions ParseCliOptions(int argc, char** argv) {
  CliOptions options;
  for (int i = 1; i < argc; ++i) {
    const std::string_view arg = argv[i] != nullptr ? argv[i] : "";
    if (arg == "--once") {
      options.once = true;
    } else if (arg == "--format" && i + 1 < argc) {
      const std::string_view value = argv[++i] != nullptr ? argv[i] : "";
      if (value == "text") {
        options.format = OutputFormat::Text;
      } else if (value == "json") {
        options.format = OutputFormat::Json;
      } else {
        options.invalidFormat = true;
        options.invalidFormatValue = std::string(value);
      }
    }
  }
  return options;
}

// Shared setup used by both the interactive loop and one-shot mode: resolves data paths, enforces
// the single-instance lock, loads settings, and constructs the platform HTTP/process/secret
// backends providers depend on. Returns nullopt (after printing an error and setting `exitCode`)
// if the process should exit immediately instead of proceeding.
struct ConsoleSession {
  DataPaths paths;
  Settings settings;
  std::unique_ptr<IHttpClient> http;
  std::unique_ptr<IProcessRunner> process;
  std::unique_ptr<ISecretStore> secrets;
  std::unique_ptr<ISingleInstanceSignal> instanceSignal;
};

std::optional<ConsoleSession> PrepareConsoleSession(char** argv, int& exitCode) {
  ConsoleSession session;
  const auto executable = std::filesystem::path(argv != nullptr && argv[0] != nullptr ? argv[0] : "");
  session.paths = ResolveDataPaths(executable);

  session.instanceSignal = CreatePlatformSingleInstanceSignal(session.paths.root);
  if (session.instanceSignal->IsAnotherRunning()) {
    session.instanceSignal->SignalActivation();
    std::cerr << "AI Usage Monitor ya se está ejecutando; revise el icono de bandeja o la consola activa.\n";
    exitCode = 1;
    return std::nullopt;
  }
  (void)session.instanceSignal->ConsumeActivation();

  const auto loaded = LoadSettings(session.paths);
  session.settings = loaded.settings;
  if (!loaded.warning.empty()) std::cerr << "Aviso: " << loaded.warning << "\n";

  session.http = CreatePlatformHttpClient();
  session.process = CreatePlatformProcessRunner();
  session.secrets = CreatePlatformSecretStore();
  return session;
}

// Builds the ordered, per-configured-provider snapshot list from whatever has been observed so
// far, synthesizing a placeholder "waiting" entry for providers with no snapshot yet.
std::vector<ProviderSnapshot> OrderSnapshots(const Settings& settings,
                                             const std::map<std::string, ProviderSnapshot>& snapshots) {
  std::vector<ProviderSnapshot> ordered;
  for (const auto& config : settings.providers) {
    const auto found = snapshots.find(config.id);
    if (found != snapshots.end()) {
      ordered.push_back(found->second);
    } else {
      ProviderSnapshot snapshot;
      snapshot.providerId = config.id;
      snapshot.displayName = config.name;
      snapshot.kind = config.kind;
      snapshot.health = config.enabled ? Health::Partial : Health::Disabled;
      snapshot.freshness = Freshness::NoData;
      if (config.enabled) {
        snapshot.error = ProviderError{"waiting", "Esperando primera actualización", true, std::nullopt};
      }
      ordered.push_back(std::move(snapshot));
    }
  }
  return ordered;
}

constexpr std::chrono::seconds kOnceFetchTimeout{30};

// Refreshes every enabled provider once and blocks until each has reported (or the bounded
// timeout elapses), returning the resulting ordered snapshot list. Providers that time out fall
// back to whatever was already loaded from cache, mirroring the "no data yet" placeholder the
// interactive loop shows before its first successful refresh.
std::vector<ProviderSnapshot> FetchSnapshotsOnce(const ConsoleSession& session) {
  std::mutex snapshotsMutex;
  std::condition_variable resultsReady;
  std::map<std::string, ProviderSnapshot> snapshots;
  for (auto& snapshot : LoadCache(session.paths)) snapshots[snapshot.providerId] = std::move(snapshot);

  std::size_t enabledCount = 0;
  for (const auto& config : session.settings.providers) {
    if (config.enabled) ++enabledCount;
  }

  std::size_t reported = 0;
  RefreshScheduler scheduler([&](const ProviderSnapshot& snapshot) {
    std::lock_guard<std::mutex> lock(snapshotsMutex);
    const auto found = snapshots.find(snapshot.providerId);
    if (snapshot.health == Health::Error && found != snapshots.end() && !found->second.metrics.empty()) {
      auto stale = found->second;
      stale.freshness = Freshness::Stale;
      stale.health = Health::Error;
      stale.error = snapshot.error;
      snapshots[snapshot.providerId] = std::move(stale);
    } else {
      snapshots[snapshot.providerId] = snapshot;
    }
    ++reported;
    resultsReady.notify_all();
  });
  scheduler.SetProviders(BuildProviders(session.settings, *session.http, *session.process, *session.secrets));
  scheduler.SetInterval(std::chrono::minutes{session.settings.refreshMinutes});
  scheduler.Start();
  scheduler.RefreshAll();

  {
    std::unique_lock<std::mutex> lock(snapshotsMutex);
    resultsReady.wait_for(lock, kOnceFetchTimeout, [&] { return reported >= enabledCount; });
  }
  scheduler.Stop();

  std::lock_guard<std::mutex> lock(snapshotsMutex);
  auto ordered = OrderSnapshots(session.settings, snapshots);

  std::vector<ProviderSnapshot> cache;
  for (const auto& [id, value] : snapshots) {
    (void)id;
    if (!value.metrics.empty()) cache.push_back(value);
  }
  try {
    SaveCache(session.paths, cache);
  } catch (...) {
  }
  return ordered;
}

std::string RenderOneShotText(const std::vector<ProviderSnapshot>& snapshots, TimePoint now, int width) {
  const int boxWidth = BoxWidthFor(width);
  std::ostringstream out;
  for (const auto& snapshot : snapshots) out << RenderProviderSection(snapshot, now, boxWidth) << "\n\n";
  return out.str();
}

int RunOnceAndExit(const ConsoleSession& session, OutputFormat format) {
  const auto snapshots = FetchSnapshotsOnce(session);

  if (format == OutputFormat::Json) {
    std::cout << SnapshotsToJson(snapshots) << "\n";
  } else {
    std::cout << RenderOneShotText(snapshots, Clock::now(), TerminalWidth());
  }
  std::cout.flush();

  const bool anyEnabledError = std::any_of(
      session.settings.providers.begin(), session.settings.providers.end(), [&](const ProviderConfig& config) {
        if (!config.enabled) return false;
        const auto found = std::find_if(snapshots.begin(), snapshots.end(),
                                        [&](const ProviderSnapshot& s) { return s.providerId == config.id; });
        return found != snapshots.end() && found->health == Health::Error;
      });
  return anyEnabledError ? 1 : 0;
}

int RunInteractiveDashboard(ConsoleSession session) {
  std::mutex snapshotsMutex;
  std::map<std::string, ProviderSnapshot> snapshots;
  for (auto& snapshot : LoadCache(session.paths)) snapshots[snapshot.providerId] = std::move(snapshot);

  std::atomic<bool> dirty{true};
  RefreshScheduler scheduler([&](const ProviderSnapshot& snapshot) {
    std::lock_guard<std::mutex> lock(snapshotsMutex);
    const auto found = snapshots.find(snapshot.providerId);
    if (snapshot.health == Health::Error && found != snapshots.end() && !found->second.metrics.empty()) {
      auto stale = found->second;
      stale.freshness = Freshness::Stale;
      stale.health = Health::Error;
      stale.error = snapshot.error;
      snapshots[snapshot.providerId] = std::move(stale);
    } else {
      snapshots[snapshot.providerId] = snapshot;
    }
    dirty.store(true);
  });
  scheduler.SetProviders(BuildProviders(session.settings, *session.http, *session.process, *session.secrets));
  scheduler.SetInterval(std::chrono::minutes{session.settings.refreshMinutes});
  scheduler.Start();
  scheduler.RefreshAll();

  gQuitRequested.store(false);
  std::signal(SIGINT, HandleTerminationSignal);
  std::signal(SIGTERM, HandleTerminationSignal);

  RawTerminalMode rawMode;
  auto lastRedraw = Clock::now() - kRedrawInterval;
  while (!gQuitRequested.load()) {
    const auto key = PollKeyPress(kInputPollTimeout);
    if (key.has_value()) {
      const char pressed = static_cast<char>(std::tolower(static_cast<unsigned char>(*key)));
      if (pressed == 'q') break;
      if (pressed == 'r') {
        scheduler.RefreshAll();
        dirty.store(true);
      }
    }

    const auto now = Clock::now();
    if (dirty.exchange(false) || now - lastRedraw >= kRedrawInterval) {
      lastRedraw = now;
      std::vector<ProviderSnapshot> ordered;
      {
        std::lock_guard<std::mutex> lock(snapshotsMutex);
        ordered = OrderSnapshots(session.settings, snapshots);
      }
      std::cout << RenderDashboard(ordered, now, TerminalWidth());
      std::cout.flush();
    }
  }

  scheduler.Stop();
  {
    std::lock_guard<std::mutex> lock(snapshotsMutex);
    std::vector<ProviderSnapshot> cache;
    for (const auto& [id, value] : snapshots) {
      (void)id;
      if (!value.metrics.empty()) cache.push_back(value);
    }
    try {
      SaveCache(session.paths, cache);
    } catch (...) {
    }
  }
  std::cout << "\nAI Usage Monitor (consola) detenido.\n";
  return 0;
}

}  // namespace

int RunConsoleDashboard(int argc, char** argv) {
  const auto options = ParseCliOptions(argc, argv);
  if (options.invalidFormat) {
    std::cerr << "Formato no soportado: \"" << options.invalidFormatValue << "\" (use \"text\" o \"json\").\n";
    return 1;
  }

  int exitCode = 1;
  auto session = PrepareConsoleSession(argv, exitCode);
  if (!session.has_value()) return exitCode;

  if (options.once) return RunOnceAndExit(*session, options.format);
  return RunInteractiveDashboard(std::move(*session));
}

}  // namespace ai_usage::console
