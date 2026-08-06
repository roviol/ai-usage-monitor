#pragma once

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

}  // namespace ai_usage
