#pragma once

#include "ai_usage/domain.h"

#include <string>
#include <vector>

namespace ai_usage::console {

// Renders a `[####------] 42%` style bar for a used-percentage value clamped to [0, 100].
std::string RenderProgressBar(int usedPercent, int width);

// Renders the full multi-line text block for one provider, mirroring the content shown by the
// desktop provider card (name, health, observation time, metrics with progress bars and reset
// countdowns, provenance, and cached-but-errored state).
std::string RenderProviderSection(const ProviderSnapshot& snapshot, TimePoint now, int width);

// Renders the full screen: a header line followed by every provider section and a footer with
// the available key commands.
std::string RenderDashboard(const std::vector<ProviderSnapshot>& snapshots, TimePoint now, int width);

// Entry point for `--console` mode on Linux. Loads the shared settings/cache, builds providers,
// drives the shared scheduler, and renders the text dashboard until the user quits. Returns a
// process exit code. Also accepts `--once` for a single-shot refresh-print-exit run, and
// `--format text|json` to select the one-shot output format (defaults to `text`).
int RunConsoleDashboard(int argc, char** argv);

// Serializes provider snapshots to a single JSON array for scriptable one-shot output.
std::string SnapshotsToJson(const std::vector<ProviderSnapshot>& snapshots);

}  // namespace ai_usage::console
