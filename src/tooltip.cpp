#include "ai_usage/tooltip.h"

#include <algorithm>
#include <cmath>
#include <iomanip>
#include <sstream>

namespace ai_usage {
namespace {

int Priority(const ProviderSnapshot& snapshot) {
  if (snapshot.health == Health::Error) return 0;
  if (snapshot.health == Health::Partial || snapshot.freshness == Freshness::Stale) return 1;
  if (snapshot.health == Health::Healthy) return 2;
  return 3;
}

std::string AgeText(const ProviderSnapshot& snapshot, TimePoint now) {
  if (snapshot.observedAt == TimePoint{}) return "sin datos";
  const auto elapsed = now > snapshot.observedAt ? now - snapshot.observedAt : Clock::duration::zero();
  const auto minutes = std::chrono::duration_cast<std::chrono::minutes>(elapsed).count();
  if (minutes < 1) return "ahora";
  if (minutes < 60) return std::to_string(minutes) + "m";
  const auto hours = minutes / 60;
  if (hours < 48) return std::to_string(hours) + "h";
  return std::to_string(hours / 24) + "d";
}

}  // namespace

std::string FormatMetric(const Metric& metric) {
  if (metric.availability != Availability::Available) return "N/D";
  std::ostringstream output;
  if (metric.kind == MetricKind::Balance || metric.kind == MetricKind::Spent) {
    output << metric.value << ' ' << ToString(metric.unit);
  } else if (metric.unit == MetricUnit::Percent) {
    output << metric.value << '%';
  } else {
    output << metric.value << ' ' << ToString(metric.unit);
  }
  return output.str();
}

std::string ComposeTooltip(const std::vector<ProviderSnapshot>& snapshots, TimePoint now, std::size_t maxCharacters) {
  if (maxCharacters == 0U) return {};
  const auto aggregate = AggregateHealth(snapshots);
  auto ordered = snapshots;
  std::stable_sort(ordered.begin(), ordered.end(), [](const auto& left, const auto& right) {
    if (Priority(left) != Priority(right)) return Priority(left) < Priority(right);
    if (left.displayName != right.displayName) return left.displayName < right.displayName;
    return left.providerId < right.providerId;
  });
  std::vector<std::string> parts;
  parts.push_back("IA: " + ToString(aggregate));
  for (const auto& snapshot : ordered) {
    if (snapshot.health == Health::Disabled) continue;
    std::string part = snapshot.displayName + ": ";
    if (snapshot.error.has_value()) {
      part += snapshot.error->code;
    } else {
      const auto metric = std::find_if(snapshot.metrics.begin(), snapshot.metrics.end(), [](const Metric& candidate) {
        return candidate.availability == Availability::Available &&
               (candidate.kind == MetricKind::UsedPercent || candidate.kind == MetricKind::Balance ||
                candidate.kind == MetricKind::TotalTokens);
      });
      part += metric == snapshot.metrics.end() ? "sin datos" : FormatMetric(*metric);
    }
    part += " " + AgeText(snapshot, now);
    if (snapshot.freshness == Freshness::Stale) part += " stale";
    parts.push_back(std::move(part));
  }
  std::string result;
  for (std::size_t index = 0; index < parts.size(); ++index) {
    const auto& part = parts[index];
    const std::string candidate = result.empty() ? part : result + " | " + part;
    if (candidate.size() > maxCharacters) {
      if (index == 1U && result.size() + 3U < maxCharacters) {
        result += " | " + part.substr(0, maxCharacters - result.size() - 3U);
      }
      break;
    }
    result = candidate;
  }
  if (result.empty()) result = "AI Usage Monitor";
  if (result.size() > maxCharacters) result.resize(maxCharacters);
  return result;
}

}  // namespace ai_usage
