#pragma once

#include "ai_usage/domain.h"

#include <cstddef>
#include <string>
#include <vector>

namespace ai_usage {

std::string ComposeTooltip(const std::vector<ProviderSnapshot>& snapshots, TimePoint now, std::size_t maxCharacters = 127U);
std::string FormatMetric(const Metric& metric);

}  // namespace ai_usage
