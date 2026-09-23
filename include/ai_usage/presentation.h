#pragma once

#include "ai_usage/domain.h"

#include <string>

namespace ai_usage {

struct PresentationRgb {
  int red{0};
  int green{0};
  int blue{0};
};

double RelativeLuminance(PresentationRgb colour);
double ContrastRatio(PresentationRgb foreground, PresentationRgb background);
PresentationRgb EnsureTextContrast(PresentationRgb preferred, PresentationRgb background,
                                   PresentationRgb lightFallback = {255, 255, 255},
                                   PresentationRgb darkFallback = {18, 24, 38}, double minimumRatio = 4.5);
bool UseCompactLayout(int logicalWidth, int breakpoint = 640);
int ScaleForDpi(int logicalPixels, int scalePercent);

// The reset line shown on a dashboard card: "Reinicia <system-local time>  ·
//  reinicia en Xm". Shared by the card and the accessibility labels so both
// read identically; clock supplies the current moment for the countdown.
std::string FormatResetMetadata(const Metric& metric, TimePoint now);

}  // namespace ai_usage
