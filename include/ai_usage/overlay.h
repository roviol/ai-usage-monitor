#pragma once

#include "ai_usage/domain.h"

#include <cstddef>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace ai_usage {

enum class OverlayCorner { TopLeft, TopRight, BottomLeft, BottomRight };

struct OverlayRow {
  std::string providerId;
  std::string providerName;
  std::string label;
  std::string value;
  std::optional<double> usedPercent;
  std::optional<TimePoint> resetsAt;
  std::string resetText;
  std::string statusText;
};

struct OverlayProjection {
  std::vector<OverlayRow> rows;
  std::size_t hiddenCount{0};
};

int NormalizeOverlayOpacity(int opacity);
int NormalizeOverlayMargin(int margin);
std::string SelectOverlayMonitor(std::string_view savedMonitor, const std::vector<std::string>& availableMonitors,
                                 std::string_view primaryMonitor);
OverlayCorner NearestOverlayCorner(int windowX, int windowY, int windowWidth, int windowHeight,
                                   int workLeft, int workTop, int workRight, int workBottom, int margin);
bool CoversOverlayMonitor(int windowLeft, int windowTop, int windowRight, int windowBottom,
                          int monitorLeft, int monitorTop, int monitorRight, int monitorBottom);
std::string FormatResetCountdown(std::optional<TimePoint> resetsAt, TimePoint now);
std::optional<TimePoint> NextOverlayCountdownUpdate(const std::vector<OverlayRow>& rows, TimePoint now);
std::size_t OverlayRowCapacity(int workAreaHeight, int fixedHeight, int rowHeight);
OverlayProjection ProjectOverlayRows(const std::vector<ProviderSnapshot>& snapshots, TimePoint now,
                                     std::size_t capacity);

}  // namespace ai_usage
