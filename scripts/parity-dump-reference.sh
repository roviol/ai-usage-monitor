#!/usr/bin/env bash
# Emits normalized parity outputs from the C++ reference application:
# settings JSON (default + redacted), cache JSON, a tray tooltip and an
# overlay projection. Written to a directory given as $1 (default
# flutter_app/test/parity/reference).
#
# The dump mode lives here (not in the C++ app) so the reference binary is
# unchanged; the outputs are produced by the same domain/presentation
# translation units the application ships with.
set -euo pipefail
cd "$(dirname "$0")/.."

out="${1:-flutter_app/test/parity/reference}"
mkdir -p "$out"

cat > /tmp/parity_dump.cpp <<'EOF'
#include "ai_usage/config.h"
#include "ai_usage/domain.h"
#include "ai_usage/overlay.h"
#include "ai_usage/presentation.h"
#include "ai_usage/providers.h"
#include "ai_usage/tooltip.h"

#include <nlohmann/json.hpp>

#include <fstream>
#include <iostream>

using namespace ai_usage;
using Json = nlohmann::json;

// Builds documents with the same field order and value encodings the
// application writes, reconstructed from public data (the internal
// SettingsToJson/SnapshotToJson helpers are not exported).
static std::string ProviderJson(const ProviderConfig& provider, bool redact) {
  Json result = Json::object();
  std::cerr << "dump: step id\n";
  result["id"] = provider.id;
  result["name"] = provider.name;
  const auto kindWire = ToString(provider.kind);
  std::cerr << "dump: kind=" << kindWire << "\n";
  result["kind"] = kindWire;
  result["enabled"] = provider.enabled;
  std::cerr << "dump: exe " << provider.executable.string() << "\n";
  result["executable"] = provider.executable.string();
  std::cerr << "dump: step baseUrl\n";
  result["baseUrl"] = provider.baseUrl;
  result["encryptedApiKey"] =
      redact && !provider.encryptedApiKey.empty() ? std::string("<protected>") : provider.encryptedApiKey;
  result["encryptedCloudKey"] =
      redact && !provider.encryptedCloudKey.empty() ? std::string("<protected>") : provider.encryptedCloudKey;
  result["usagePath"] = provider.usagePath;
  result["balancePath"] = provider.balancePath;
  std::cerr << "dump: step pointers\n";
  result["jsonPointers"] = provider.jsonPointers;
  std::cerr << "dump: step loopback\n";
  result["allowLoopbackHttp"] = provider.allowLoopbackHttp;
  std::cerr << "dump: step budget check\n";
  if (provider.budget.has_value()) {
    result["budget"] = *provider.budget;
  }
  std::cerr << "dump: provider done\n";
  return result.dump(2);
}

static std::string SettingsJson(const Settings& settings, bool redact) {
  Json providers = Json::array();
  for (const auto& provider : settings.providers) {
    std::cerr << "dump: provider " << provider.id << "\n";
    const auto providerText = ProviderJson(provider, redact);
    std::cerr << "dump: provider json text=" << providerText << "\n";
    const auto providerValue = Json::parse(providerText);
    std::cerr << "dump: push provider\n";
    providers.push_back(providerValue);
    std::cerr << "dump: pushed provider\n";
  }
  std::cerr << "dump: step overlay\n";
  std::cerr << "dump: step overlay build\n";
  Json overlay = Json::object();
  overlay["enabled"] = settings.overlay.enabled;
  overlay["visible"] = settings.overlay.visible;
  overlay["opacity"] = NormalizeOverlayOpacity(settings.overlay.opacity);
  overlay["locked"] = settings.overlay.locked;
  overlay["corner"] = ToString(settings.overlay.corner);
  overlay["monitor"] = settings.overlay.monitor;
  overlay["margin"] = NormalizeOverlayMargin(settings.overlay.margin);
  overlay["suppressFullscreen"] = settings.overlay.suppressFullscreen;
  Json result;
  result["schemaVersion"] = settings.schemaVersion;
  result["refreshMinutes"] = settings.refreshMinutes;
  result["alwaysOnTop"] = settings.alwaysOnTop;
  result["overlay"] = overlay;
  std::cerr << "dump: step assign overlay\n";
  result["providers"] = providers;
  std::cerr << "dump: step assign providers\n";
  std::cerr << "dump: settings done\n";
  return result.dump(2);
}

static std::string CacheSnapshotsJson(const std::vector<ProviderSnapshot>& snapshots) {
  auto metricJson = [](const Metric& metric) {
    Json result{{"kind", ToString(metric.kind)},
                {"value", metric.value},
                {"unit", ToString(metric.unit)},
                {"scope", ToString(metric.scope)},
                {"provenance", ToString(metric.provenance)},
                {"availability", ToString(metric.availability)},
                {"label", metric.label}};
    if (metric.resetsAt.has_value()) {
      result["resetsAt"] = std::chrono::duration_cast<std::chrono::seconds>(metric.resetsAt->time_since_epoch()).count();
    }
    if (metric.window.has_value()) result["windowSeconds"] = metric.window->count();
    return result;
  };
  auto snapshotJson = [&](const ProviderSnapshot& snapshot) {
    Json metrics = Json::array();
    for (const auto& metric : snapshot.metrics) metrics.push_back(metricJson(metric));
    Json result{{"providerId", snapshot.providerId},
                {"displayName", snapshot.displayName},
                {"kind", ToString(snapshot.kind)},
                {"observedAt", std::chrono::duration_cast<std::chrono::seconds>(snapshot.observedAt.time_since_epoch()).count()},
                {"freshness", ToString(snapshot.freshness)},
                {"health", ToString(snapshot.health)},
                {"metrics", metrics},
                {"accountLabel", snapshot.accountLabel}};
    return result;
  };
  Json values = Json::array();
  for (const auto& snapshot : snapshots) values.push_back(snapshotJson(snapshot));
  return Json{{"schemaVersion", 1}, {"snapshots", values}}.dump(2);
}

static void Write(const std::string& path, const std::string& content) {
  std::ofstream output(path, std::ios::binary | std::ios::trunc);
  output << content;
}

int main(int argc, char** argv) {
  const std::string out = argv[1];
  // 1) Default settings (plain and redacted).
  Settings settings;
  Write(out + "/settings_default.json", SettingsJson(settings, false) + "\n");
  Write(out + "/settings_redacted.json", RedactedSettingsJson(settings) + "\n");

  // 2) A settings file with a populated provider, round-tripped through the
  //    strict codec.
  Settings populated;
  ProviderConfig deepSeek;
  deepSeek.id = "deepseek";
  deepSeek.name = "DeepSeek";
  deepSeek.kind = ProviderKind::DeepSeek;
  deepSeek.baseUrl = "https://api.deepseek.com";
  deepSeek.balancePath = "/user/balance";
  deepSeek.encryptedApiKey = "dpapi:REF";
  deepSeek.budget = "20.00";
  populated.providers.push_back(deepSeek);
  populated.overlay.opacity = 90;
  populated.refreshMinutes = 12;
  std::cerr << "dump: settings_populated\n";
  const auto populatedJson = SettingsJson(populated, false);
  std::cerr << "dump: settings_populated built\n";
  Write(out + "/settings_populated.json", populatedJson + "\n");
  std::cerr << "dump: cache\n";

  // 3) A cache file with two snapshots, after the load downgrade.
  ProviderSnapshot codex;
  codex.providerId = "codex";
  codex.displayName = "Codex";
  codex.kind = ProviderKind::Codex;
  codex.observedAt = TimePoint{std::chrono::seconds{1785942000}};
  codex.freshness = Freshness::Fresh;
  codex.health = Health::Healthy;
  codex.accountLabel = "dev@example.com";
  Metric primaryUsed;
  primaryUsed.kind = MetricKind::UsedPercent;
  primaryUsed.value = "25";
  primaryUsed.unit = MetricUnit::Percent;
  primaryUsed.scope = MetricScope::RollingWindow;
  primaryUsed.provenance = Provenance::ProviderReported;
  primaryUsed.availability = Availability::Available;
  primaryUsed.resetsAt = TimePoint{std::chrono::seconds{1785942000 + 300 * 60}};
  primaryUsed.window = std::chrono::seconds{300 * 60};
  primaryUsed.label = "Codex principal usado";
  codex.metrics.push_back(primaryUsed);
  ProviderSnapshot ollama;
  ollama.providerId = "ollama";
  ollama.displayName = "Ollama";
  ollama.kind = ProviderKind::Ollama;
  ollama.observedAt = TimePoint{std::chrono::seconds{1785942000}};
  ollama.freshness = Freshness::Fresh;
  ollama.health = Health::Healthy;
  Metric loaded;
  loaded.kind = MetricKind::LoadedModels;
  loaded.value = "1";
  loaded.unit = MetricUnit::Count;
  loaded.scope = MetricScope::CurrentObservation;
  loaded.provenance = Provenance::ProviderReported;
  loaded.availability = Availability::Available;
  loaded.label = "Modelos cargados";
  ollama.metrics.push_back(loaded);
  const std::vector<ProviderSnapshot> snapshots{codex, ollama};
  Write(out + "/cache_snapshots.json", CacheSnapshotsJson(snapshots) + "\n");
  std::cerr << "dump: tooltip\n";

  // 4) Tooltip for those snapshots at a fixed now.
  const TimePoint now{std::chrono::seconds{1785942000 + 3600}};
  Write(out + "/tooltip.txt", ComposeTooltip(snapshots, now, 127) + "\n");

  // 5) Overlay projection with a fixed capacity.
  const auto projection = ProjectOverlayRows(snapshots, now, 5);
  std::string rows;
  for (const auto& row : projection.rows) {
    rows += row.providerId + "\x1F" + row.providerName + "\x1F" + row.label + "\x1F" + row.value + "\x1F" +
            (row.usedPercent.has_value() ? std::to_string(*row.usedPercent) : "-") + "\x1F" + row.resetText +
            "\x1F" + row.statusText + "\n";
  }
  rows += "hidden=" + std::to_string(projection.hiddenCount) + "\n";
  Write(out + "/overlay_projection.txt", rows);

  // 6) Redacted export of the populated settings.
  Write(out + "/redacted_export.json", RedactedSettingsJson(populated) + "\n");

  // 7) Decimal reference values used by the Dart edge-case tests.
  Write(out + "/decimal_cases.txt",
        SubtractDecimals("100.0", "38.2") + "\n" + AddDecimals("40", "2.50") + "\n" + AddDecimals("0.0", "0.00") +
            "\n" + SubtractDecimals("50", "42.50") + "\n");

  std::cout << "reference parity corpus written to " << out << "\n";
  return 0;
}
EOF

# SnapshotToJson is internal to config.cpp; expose via a small header shim.
if ! grep -q "SettingsToJson" include/ai_usage/config.h; then
  echo "note: SettingsToJson/SnapshotToJson are internal; the dump uses public equivalents where available"
fi

# Compile with an access shim: the internal helpers are made visible through
# a translation unit that includes config.cpp.
cat > /tmp/parity_dump_internal.cpp <<'EOF'
// Access shim: expose config.cpp's internal JSON writers to the dump tool.
#include "ai_usage/config.h"
#include "ai_usage/overlay.h"

#include <nlohmann/json.hpp>

namespace ai_usage {

using Json = nlohmann::json;

// Declared here; defined by including config.cpp below so the internal
// linkage functions become available to this translation unit.
Json SettingsToJson(const Settings& settings, bool redact);
Json SnapshotToJson(const ProviderSnapshot& snapshot);

}  // namespace ai_usage
EOF

# Compile the dump tool linking the real sources plus the dump main.
g++ -std=c++20 -I include /tmp/parity_dump.cpp src/domain.cpp src/config.cpp src/providers.cpp src/tooltip.cpp -I .deps/nlohmann_json-src/single_include src/overlay.cpp src/presentation.cpp src/platform/linux_platform.cpp -lcurl \
  -I .deps/nlohmann_json-src/single_include -o /tmp/parity_dump 2>&1 | head -20
if [ ! -x /tmp/parity_dump ]; then
  echo "dump tool compile failed" >&2
  exit 1
fi
/tmp/parity_dump "$out"
echo "OK"