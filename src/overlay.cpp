#include "ai_usage/overlay.h"

#include "ai_usage/tooltip.h"

#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <limits>

namespace ai_usage {
namespace {

std::optional<double> ParsePercent(const Metric& metric) {
  if (metric.kind != MetricKind::UsedPercent || metric.availability != Availability::Available) {
    return std::nullopt;
  }
  char* end = nullptr;
  const double value = std::strtod(metric.value.c_str(), &end);
  if (end == metric.value.c_str() || *end != '\0' || !std::isfinite(value)) return std::nullopt;
  return std::clamp(value, 0.0, 100.0);
}

std::string RowStatus(const ProviderSnapshot& snapshot) {
  if (snapshot.error.has_value() && snapshot.error->code == "refreshing") return "actualizando";
  if (snapshot.health == Health::Error) {
    return snapshot.freshness == Freshness::Stale ? "error · anterior" : "error";
  }
  if (snapshot.freshness == Freshness::Stale) return "anterior";
  if (snapshot.health == Health::Partial) return "parcial";
  if (snapshot.health == Health::Disabled) return "desactivado";
  if (snapshot.freshness == Freshness::NoData) return "sin datos";
  return {};
}

OverlayRow MakeStatusRow(const ProviderSnapshot& snapshot) {
  auto status = RowStatus(snapshot);
  if (status.empty()) status = "sin datos";
  return {snapshot.providerId, snapshot.displayName, "Estado", status, std::nullopt, std::nullopt, {}, status};
}

}  // namespace

int NormalizeOverlayOpacity(int opacity) { return std::clamp(opacity, 50, 100); }

int NormalizeOverlayMargin(int margin) { return std::clamp(margin, 0, 96); }

std::string SelectOverlayMonitor(std::string_view savedMonitor, const std::vector<std::string>& availableMonitors,
                                 std::string_view primaryMonitor) {
  const auto contains = [&availableMonitors](std::string_view value) {
    return std::find(availableMonitors.begin(), availableMonitors.end(), value) != availableMonitors.end();
  };
  if (!savedMonitor.empty() && contains(savedMonitor)) return std::string(savedMonitor);
  if (!primaryMonitor.empty() && contains(primaryMonitor)) return std::string(primaryMonitor);
  return availableMonitors.empty() ? std::string{} : availableMonitors.front();
}

OverlayCorner NearestOverlayCorner(int windowX, int windowY, int windowWidth, int windowHeight,
                                   int workLeft, int workTop, int workRight, int workBottom, int margin) {
  const int left = workLeft + margin;
  const int right = workRight - windowWidth - margin;
  const int top = workTop + margin;
  const int bottom = workBottom - windowHeight - margin;
  const bool chooseRight = std::abs(windowX - right) < std::abs(windowX - left);
  const bool chooseBottom = std::abs(windowY - bottom) < std::abs(windowY - top);
  return chooseBottom ? (chooseRight ? OverlayCorner::BottomRight : OverlayCorner::BottomLeft)
                      : (chooseRight ? OverlayCorner::TopRight : OverlayCorner::TopLeft);
}

bool CoversOverlayMonitor(int windowLeft, int windowTop, int windowRight, int windowBottom,
                          int monitorLeft, int monitorTop, int monitorRight, int monitorBottom) {
  return windowLeft <= monitorLeft && windowTop <= monitorTop && windowRight >= monitorRight &&
         windowBottom >= monitorBottom;
}

std::string FormatResetCountdown(std::optional<TimePoint> resetsAt, TimePoint now) {
  if (!resetsAt.has_value()) return {};
  const auto remaining = std::chrono::duration_cast<std::chrono::seconds>(*resetsAt - now).count();
  if (remaining <= 0) return "reiniciando";
  if (remaining < 60) return "reinicia en <1m";

  const auto minutes = (remaining + 59) / 60;
  if (minutes < 60) return "reinicia en " + std::to_string(minutes) + "m";
  const auto hours = minutes / 60;
  const auto minutePart = minutes % 60;
  if (hours < 24) {
    return "reinicia en " + std::to_string(hours) + "h" +
           (minutePart == 0 ? std::string{} : " " + std::to_string(minutePart) + "m");
  }
  const auto days = hours / 24;
  const auto hourPart = hours % 24;
  return "reinicia en " + std::to_string(days) + "d" +
         (hourPart == 0 ? std::string{} : " " + std::to_string(hourPart) + "h");
}

std::string FormatUnloadCountdown(std::optional<TimePoint> resetsAt, TimePoint now) {
  if (!resetsAt.has_value()) return {};
  const auto remaining = std::chrono::duration_cast<std::chrono::seconds>(*resetsAt - now).count();
  if (remaining <= 0) return "descargando";
  if (remaining < 60) return "descarga en <1m";

  const auto minutes = (remaining + 59) / 60;
  if (minutes < 60) return "descarga en " + std::to_string(minutes) + "m";
  const auto hours = minutes / 60;
  const auto minutePart = minutes % 60;
  if (hours < 24) {
    return "descarga en " + std::to_string(hours) + "h" +
           (minutePart == 0 ? std::string{} : " " + std::to_string(minutePart) + "m");
  }
  const auto days = hours / 24;
  const auto hourPart = hours % 24;
  return "descarga en " + std::to_string(days) + "d" +
         (hourPart == 0 ? std::string{} : " " + std::to_string(hourPart) + "h");
}

std::optional<TimePoint> NextOverlayCountdownUpdate(const std::vector<OverlayRow>& rows, TimePoint now) {
  std::optional<TimePoint> earliestReset;
  bool hasFutureReset = false;
  for (const auto& row : rows) {
    if (!row.resetsAt.has_value() || *row.resetsAt <= now) continue;
    hasFutureReset = true;
    if (!earliestReset.has_value() || *row.resetsAt < *earliestReset) earliestReset = row.resetsAt;
  }
  if (!hasFutureReset) return std::nullopt;
  const auto sinceEpoch = std::chrono::duration_cast<std::chrono::seconds>(now.time_since_epoch());
  const auto nextMinute = TimePoint{std::chrono::duration_cast<Clock::duration>(
      std::chrono::seconds{(sinceEpoch.count() / 60 + 1) * 60})};
  return std::min(nextMinute, *earliestReset);
}

std::size_t OverlayRowCapacity(int workAreaHeight, int fixedHeight, int rowHeight) {
  if (workAreaHeight <= 0 || rowHeight <= 0) return 0;
  const int maximum = static_cast<int>(std::floor(workAreaHeight * 0.4));
  if (maximum <= fixedHeight) return 0;
  return static_cast<std::size_t>((maximum - fixedHeight) / rowHeight);
}

OverlayProjection ProjectOverlayRows(const std::vector<ProviderSnapshot>& snapshots, TimePoint now,
                                     std::size_t capacity) {
  std::vector<OverlayRow> projected;
  for (const auto& snapshot : snapshots) {
    const auto status = RowStatus(snapshot);
    const auto before = projected.size();
    for (const auto& metric : snapshot.metrics) {
      if (metric.kind == MetricKind::RemainingPercent || metric.availability != Availability::Available) continue;
      const bool instantaneous = metric.kind == MetricKind::LoadedModels ||
                                 metric.kind == MetricKind::ResourceMemory;
      if (!instantaneous && metric.kind != MetricKind::UsedPercent && metric.kind != MetricKind::Balance &&
          metric.kind != MetricKind::Spent) {
        continue;
      }
      const auto percent = ParsePercent(metric);
      if (metric.kind == MetricKind::UsedPercent && !percent.has_value()) continue;
      const auto label = metric.label.empty()
                             ? (metric.kind == MetricKind::Balance ? std::string{"Balance"} : std::string{"Uso"})
                             : metric.label;
      const auto resetText = metric.kind == MetricKind::ResourceMemory
                                 ? FormatUnloadCountdown(metric.resetsAt, now)
                                 : FormatResetCountdown(metric.resetsAt, now);
      projected.push_back({snapshot.providerId, snapshot.displayName, label, FormatMetric(metric), percent,
                           metric.resetsAt, resetText, status});
    }
    if (projected.size() == before &&
        (snapshot.health != Health::Healthy || snapshot.freshness != Freshness::Fresh)) {
      projected.push_back(MakeStatusRow(snapshot));
    }
  }

  OverlayProjection result;
  if (projected.size() <= capacity) {
    result.rows = std::move(projected);
    return result;
  }
  const auto visible = capacity == 0 ? 0U : capacity - 1U;
  result.hiddenCount = projected.size() - visible;
  result.rows.assign(projected.begin(), projected.begin() + static_cast<std::ptrdiff_t>(visible));
  return result;
}

}  // namespace ai_usage
