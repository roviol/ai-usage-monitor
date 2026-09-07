#pragma once

#include <chrono>
#include <optional>
#include <string>
#include <vector>

namespace ai_usage {

using Clock = std::chrono::system_clock;
using TimePoint = Clock::time_point;

enum class ProviderKind { Codex, ClaudeSubscription, DeepSeek, OpenAiCompatible, Ollama };
enum class MetricKind { UsedPercent, RemainingPercent, InputTokens, OutputTokens, TotalTokens, Balance, Spent, Requests, LoadedModels, ResourceMemory };
enum class MetricUnit { Percent, Tokens, Requests, USD, CNY, Seconds, Count, Bytes, Unknown };
enum class MetricScope { RollingWindow, Day, BillingPeriod, Lifetime, CurrentBalance, CurrentObservation };
enum class Provenance { ProviderReported, CliBridge, LocallyObserved, Derived };
enum class Availability { Available, Unsupported, Unauthorized, Unavailable, Disabled };
enum class Freshness { Fresh, Stale, NoData };
enum class Health { Healthy, Partial, Error, Disabled };

struct Metric {
  MetricKind kind{MetricKind::TotalTokens};
  std::string value;
  MetricUnit unit{MetricUnit::Unknown};
  MetricScope scope{MetricScope::Lifetime};
  Provenance provenance{Provenance::ProviderReported};
  Availability availability{Availability::Available};
  std::optional<TimePoint> resetsAt;
  std::optional<std::chrono::seconds> window;
  std::string label;
};

struct ProviderError {
  std::string code;
  std::string message;
  bool transient{false};
  std::optional<std::chrono::seconds> retryAfter;
};

struct ProviderSnapshot {
  std::string providerId;
  std::string displayName;
  ProviderKind kind{ProviderKind::OpenAiCompatible};
  TimePoint observedAt{};
  Freshness freshness{Freshness::NoData};
  Health health{Health::Disabled};
  std::vector<Metric> metrics;
  std::optional<ProviderError> error;
  std::string accountLabel;
};

struct ValidationResult {
  bool valid{true};
  std::vector<std::string> errors;
};

struct MetricAggregationResult {
  bool valid{false};
  std::optional<Metric> metric;
  std::string error;
};

ValidationResult ValidateSnapshot(const ProviderSnapshot& snapshot);
MetricAggregationResult AggregateMetrics(const std::vector<Metric>& metrics);
Health AggregateHealth(const std::vector<ProviderSnapshot>& snapshots);
bool IsDecimal(const std::string& value);
std::string AddDecimals(const std::string& left, const std::string& right);
std::string SubtractDecimals(const std::string& left, const std::string& right);
std::string ToString(ProviderKind value);
std::string ToString(MetricKind value);
std::string ToString(MetricUnit value);
std::string ToString(MetricScope value);
std::string ToString(Provenance value);
std::string ToString(Availability value);
std::string ToString(Freshness value);
std::string ToString(Health value);

}  // namespace ai_usage
