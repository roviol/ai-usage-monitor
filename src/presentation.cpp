#include "ai_usage/presentation.h"

#include <algorithm>
#include <cmath>

namespace ai_usage {
namespace {

double LinearChannel(int channel) {
  const auto value = std::clamp(channel, 0, 255) / 255.0;
  return value <= 0.04045 ? value / 12.92 : std::pow((value + 0.055) / 1.055, 2.4);
}

}  // namespace

double RelativeLuminance(PresentationRgb colour) {
  return 0.2126 * LinearChannel(colour.red) + 0.7152 * LinearChannel(colour.green) +
         0.0722 * LinearChannel(colour.blue);
}

double ContrastRatio(PresentationRgb foreground, PresentationRgb background) {
  const auto first = RelativeLuminance(foreground);
  const auto second = RelativeLuminance(background);
  const auto lighter = std::max(first, second);
  const auto darker = std::min(first, second);
  return (lighter + 0.05) / (darker + 0.05);
}

PresentationRgb EnsureTextContrast(PresentationRgb preferred, PresentationRgb background,
                                   PresentationRgb lightFallback, PresentationRgb darkFallback,
                                   double minimumRatio) {
  if (ContrastRatio(preferred, background) >= minimumRatio) return preferred;
  const auto lightRatio = ContrastRatio(lightFallback, background);
  const auto darkRatio = ContrastRatio(darkFallback, background);
  return lightRatio >= darkRatio ? lightFallback : darkFallback;
}

bool UseCompactLayout(int logicalWidth, int breakpoint) { return logicalWidth < breakpoint; }

int ScaleForDpi(int logicalPixels, int scalePercent) {
  if (logicalPixels <= 0 || scalePercent <= 0) return 0;
  return static_cast<int>(std::lround(logicalPixels * scalePercent / 100.0));
}

}  // namespace ai_usage
