#include "ai_usage/domain.h"

#include <algorithm>
#include <array>
#include <charconv>
#include <cmath>
#include <regex>
#include <stdexcept>

namespace ai_usage {
namespace {

template <typename T, std::size_t N>
std::string EnumString(T value, const std::array<std::pair<T, const char*>, N>& values) {
  const auto found = std::find_if(values.begin(), values.end(), [value](const auto& entry) { return entry.first == value; });
  return found == values.end() ? "unknown" : found->second;
}

struct DecimalParts {
  bool negative{false};
  std::string digits;
  std::size_t scale{0};
};

DecimalParts ParseDecimalParts(const std::string& value) {
  if (!IsDecimal(value)) throw std::invalid_argument("invalid decimal value");
  DecimalParts result;
  std::size_t begin = 0;
  if (value.front() == '-') {
    result.negative = true;
    begin = 1;
  }
  const auto point = value.find('.', begin);
  result.scale = point == std::string::npos ? 0 : value.size() - point - 1;
  result.digits = value.substr(begin, point == std::string::npos ? std::string::npos : point - begin);
  if (point != std::string::npos) result.digits += value.substr(point + 1);
  const auto nonZero = result.digits.find_first_not_of('0');
  result.digits = nonZero == std::string::npos ? "0" : result.digits.substr(nonZero);
  if (result.digits == "0") result.negative = false;
  return result;
}

void AlignScales(DecimalParts& left, DecimalParts& right) {
  if (left.scale < right.scale) {
    left.digits.append(right.scale - left.scale, '0');
    left.scale = right.scale;
  } else if (right.scale < left.scale) {
    right.digits.append(left.scale - right.scale, '0');
    right.scale = left.scale;
  }
}

int CompareMagnitude(const std::string& left, const std::string& right) {
  if (left.size() != right.size()) return left.size() < right.size() ? -1 : 1;
  if (left == right) return 0;
  return left < right ? -1 : 1;
}

std::string AddMagnitude(const std::string& left, const std::string& right) {
  std::string result;
  result.reserve(std::max(left.size(), right.size()) + 1);
  int carry = 0;
  for (std::size_t offset = 0; offset < std::max(left.size(), right.size()); ++offset) {
    const int lhs = offset < left.size() ? left[left.size() - offset - 1] - '0' : 0;
    const int rhs = offset < right.size() ? right[right.size() - offset - 1] - '0' : 0;
    const int sum = lhs + rhs + carry;
    result.push_back(static_cast<char>('0' + sum % 10));
    carry = sum / 10;
  }
  if (carry != 0) result.push_back(static_cast<char>('0' + carry));
  std::reverse(result.begin(), result.end());
  return result;
}

std::string SubtractMagnitude(const std::string& left, const std::string& right) {
  std::string result(left.size(), '0');
  int borrow = 0;
  for (std::size_t offset = 0; offset < left.size(); ++offset) {
    int digit = left[left.size() - offset - 1] - '0' - borrow;
    const int rhs = offset < right.size() ? right[right.size() - offset - 1] - '0' : 0;
    if (digit < rhs) {
      digit += 10;
      borrow = 1;
    } else {
      borrow = 0;
    }
    result[left.size() - offset - 1] = static_cast<char>('0' + digit - rhs);
  }
  const auto nonZero = result.find_first_not_of('0');
  return nonZero == std::string::npos ? "0" : result.substr(nonZero);
}

std::string FormatDecimal(bool negative, std::string digits, std::size_t scale) {
  if (scale > 0) {
    if (digits.size() <= scale) digits.insert(0, scale + 1 - digits.size(), '0');
    digits.insert(digits.size() - scale, 1, '.');
    while (!digits.empty() && digits.back() == '0') digits.pop_back();
    if (!digits.empty() && digits.back() == '.') digits.pop_back();
  }
  if (digits.empty()) digits = "0";
  return negative && digits != "0" ? "-" + digits : digits;
}

}  // namespace

bool IsDecimal(const std::string& value) {
  static const std::regex decimal(R"(^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$)");
  if (!std::regex_match(value, decimal)) {
    return false;
  }
  try {
    const long double parsed = std::stold(value);
    return std::isfinite(parsed);
  } catch (...) {
    return false;
  }
}

std::string AddDecimals(const std::string& left, const std::string& right) {
  auto lhs = ParseDecimalParts(left);
  auto rhs = ParseDecimalParts(right);
  AlignScales(lhs, rhs);
  if (lhs.negative == rhs.negative) {
    return FormatDecimal(lhs.negative, AddMagnitude(lhs.digits, rhs.digits), lhs.scale);
  }
  const int comparison = CompareMagnitude(lhs.digits, rhs.digits);
  if (comparison == 0) return "0";
  if (comparison > 0) return FormatDecimal(lhs.negative, SubtractMagnitude(lhs.digits, rhs.digits), lhs.scale);
  return FormatDecimal(rhs.negative, SubtractMagnitude(rhs.digits, lhs.digits), lhs.scale);
}

std::string SubtractDecimals(const std::string& left, const std::string& right) {
  return AddDecimals(left, right.starts_with('-') ? right.substr(1) : "-" + right);
}

ValidationResult ValidateSnapshot(const ProviderSnapshot& snapshot) {
  ValidationResult result;
  if (snapshot.providerId.empty()) {
    result.errors.emplace_back("providerId is required");
  }
  if (snapshot.displayName.empty()) {
    result.errors.emplace_back("displayName is required");
  }
  for (const auto& metric : snapshot.metrics) {
    if (metric.availability == Availability::Available && !IsDecimal(metric.value)) {
      result.errors.emplace_back("available metric contains a non-decimal value");
    }
    if (metric.unit == MetricUnit::Percent && metric.availability == Availability::Available) {
      const long double parsed = std::stold(metric.value);
      if (parsed < 0.0L || parsed > 100.0L) {
        result.errors.emplace_back("percentage is outside 0..100");
      }
    }
    if ((metric.unit == MetricUnit::Count || metric.unit == MetricUnit::Bytes) &&
        metric.availability == Availability::Available && std::stold(metric.value) < 0.0L) {
      result.errors.emplace_back("resource metric is negative");
    }
    if (metric.kind == MetricKind::LoadedModels && metric.unit != MetricUnit::Count) {
      result.errors.emplace_back("loaded-model metric requires count units");
    }
    if (metric.kind == MetricKind::ResourceMemory && metric.unit != MetricUnit::Bytes) {
      result.errors.emplace_back("resource-memory metric requires byte units");
    }
    if (metric.window.has_value() && metric.window->count() <= 0) {
      result.errors.emplace_back("window must be positive");
    }
  }
  result.valid = result.errors.empty();
  return result;
}

MetricAggregationResult AggregateMetrics(const std::vector<Metric>& metrics) {
  if (metrics.empty()) return {false, std::nullopt, "at least one metric is required"};
  Metric total = metrics.front();
  if (total.availability != Availability::Available || !IsDecimal(total.value)) {
    return {false, std::nullopt, "only available decimal metrics can be aggregated"};
  }
  for (std::size_t index = 1; index < metrics.size(); ++index) {
    const auto& metric = metrics[index];
    if (metric.availability != Availability::Available || !IsDecimal(metric.value)) {
      return {false, std::nullopt, "only available decimal metrics can be aggregated"};
    }
    if (metric.kind != total.kind || metric.unit != total.unit || metric.scope != total.scope ||
        metric.provenance != total.provenance || metric.resetsAt != total.resetsAt || metric.window != total.window) {
      return {false, std::nullopt, "metric kind, unit, scope, provenance and window must match"};
    }
    total.value = AddDecimals(total.value, metric.value);
  }
  return {true, std::move(total), {}};
}

Health AggregateHealth(const std::vector<ProviderSnapshot>& snapshots) {
  bool enabled = false;
  bool partial = false;
  for (const auto& snapshot : snapshots) {
    if (snapshot.health == Health::Error) {
      return Health::Error;
    }
    if (snapshot.health != Health::Disabled) {
      enabled = true;
    }
    if (snapshot.health == Health::Partial || snapshot.freshness == Freshness::Stale) {
      partial = true;
    }
  }
  if (!enabled) {
    return Health::Disabled;
  }
  return partial ? Health::Partial : Health::Healthy;
}

std::string ToString(ProviderKind value) {
  static constexpr std::array values{
      std::pair{ProviderKind::Codex, "codex"},
      std::pair{ProviderKind::ClaudeSubscription, "claude-subscription"},
      std::pair{ProviderKind::DeepSeek, "deepseek"},
      std::pair{ProviderKind::OpenAiCompatible, "openai-compatible"},
      std::pair{ProviderKind::Ollama, "ollama"}};
  return EnumString(value, values);
}

std::string ToString(MetricKind value) {
  static constexpr std::array values{
      std::pair{MetricKind::UsedPercent, "used-percent"}, std::pair{MetricKind::RemainingPercent, "remaining-percent"},
      std::pair{MetricKind::InputTokens, "input-tokens"}, std::pair{MetricKind::OutputTokens, "output-tokens"},
      std::pair{MetricKind::TotalTokens, "total-tokens"}, std::pair{MetricKind::Balance, "balance"},
      std::pair{MetricKind::Spent, "spent"}, std::pair{MetricKind::Requests, "requests"},
      std::pair{MetricKind::LoadedModels, "loaded-models"},
      std::pair{MetricKind::ResourceMemory, "resource-memory"}};
  return EnumString(value, values);
}

std::string ToString(MetricUnit value) {
  static constexpr std::array values{
      std::pair{MetricUnit::Percent, "percent"}, std::pair{MetricUnit::Tokens, "tokens"},
      std::pair{MetricUnit::Requests, "requests"}, std::pair{MetricUnit::USD, "USD"},
      std::pair{MetricUnit::CNY, "CNY"}, std::pair{MetricUnit::Seconds, "seconds"},
      std::pair{MetricUnit::Count, "count"}, std::pair{MetricUnit::Bytes, "bytes"},
      std::pair{MetricUnit::Unknown, "unknown"}};
  return EnumString(value, values);
}

std::string ToString(MetricScope value) {
  static constexpr std::array values{
      std::pair{MetricScope::RollingWindow, "rolling-window"}, std::pair{MetricScope::Day, "day"},
      std::pair{MetricScope::BillingPeriod, "billing-period"}, std::pair{MetricScope::Lifetime, "lifetime"},
      std::pair{MetricScope::CurrentBalance, "current-balance"},
      std::pair{MetricScope::CurrentObservation, "current-observation"}};
  return EnumString(value, values);
}

std::string ToString(Provenance value) {
  static constexpr std::array values{
      std::pair{Provenance::ProviderReported, "provider-reported"}, std::pair{Provenance::CliBridge, "cli-bridge"},
      std::pair{Provenance::LocallyObserved, "locally-observed"}, std::pair{Provenance::Derived, "derived"}};
  return EnumString(value, values);
}

std::string ToString(Availability value) {
  static constexpr std::array values{
      std::pair{Availability::Available, "available"}, std::pair{Availability::Unsupported, "unsupported"},
      std::pair{Availability::Unauthorized, "unauthorized"}, std::pair{Availability::Unavailable, "unavailable"},
      std::pair{Availability::Disabled, "disabled"}};
  return EnumString(value, values);
}

std::string ToString(Freshness value) {
  static constexpr std::array values{std::pair{Freshness::Fresh, "fresh"}, std::pair{Freshness::Stale, "stale"},
                                     std::pair{Freshness::NoData, "no-data"}};
  return EnumString(value, values);
}

std::string ToString(Health value) {
  static constexpr std::array values{std::pair{Health::Healthy, "healthy"}, std::pair{Health::Partial, "partial"},
                                     std::pair{Health::Error, "error"}, std::pair{Health::Disabled, "disabled"}};
  return EnumString(value, values);
}

}  // namespace ai_usage
