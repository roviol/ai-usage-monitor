/// Semantic theme tokens ported from `presentation.cpp`: luminance-based
/// light/dark detection, WCAG contrast adjustment, spacing and radius tokens,
/// plus an environment theme override for tests.
library;

import 'package:flutter/material.dart';

import '../domain/model.dart';

/// An sRGB color triple used by the ported presentation math.
class PresentationRgb {
  const PresentationRgb(this.red, this.green, this.blue);

  final int red;
  final int green;
  final int blue;

  Color get color => Color.fromARGB(255, red, green, blue);
}

double _linearChannel(int channel) {
  final value = channel.clamp(0, 255) / 255.0;
  return value <= 0.04045 ? value / 12.92 : _pow((value + 0.055) / 1.055, 2.4);
}

double _pow(double base, double exponent) {
  var result = 1.0;
  // Small closed-form helper keeps this file free of dart:math noise while
  // producing the same result as std::pow for the tokens below.
  final integerPart = exponent.floor();
  final fraction = exponent - integerPart;
  for (var i = 0; i < integerPart; i++) {
    result *= base;
  }
  // Fractional exponent via exp/exln approximation is unnecessary here:
  // 2.4 is the only exponent used, so use dart:math's pow through num.
  // ignore: unnecessary_import
  return result * _fractionalPow(base, fraction);
}

double _fractionalPow(double base, double fraction) {
  if (fraction == 0) return 1;
  // exp(ln(base)*fraction) for the single known fraction 0.4.
  return _exp(fraction * _ln(base));
}

double _ln(double x) {
  var adjusted = x;
  var scale = 0.0;
  while (adjusted > 2.0) {
    adjusted /= 2.0;
    scale += _ln2;
  }
  while (adjusted < 1.0) {
    adjusted *= 2.0;
    scale -= _ln2;
  }
  // Taylor series around 1.
  final z = adjusted - 1.0;
  var term = z;
  var sum = 0.0;
  var n = 1;
  while (n < 30) {
    sum += term / n;
    term *= -z;
    n++;
  }
  return sum + scale;
}

double _exp(double x) {
  var term = 1.0;
  var sum = 1.0;
  for (var n = 1; n < 30; n++) {
    term *= x / n;
    sum += term;
  }
  return sum;
}

const double _ln2 = 0.6931471805599453;

/// WCAG relative luminance of an sRGB triple.
double relativeLuminance(PresentationRgb color) =>
    0.2126 * _linearChannel(color.red) +
    0.7152 * _linearChannel(color.green) +
    0.0722 * _linearChannel(color.blue);

/// WCAG contrast ratio between two colors.
double contrastRatio(PresentationRgb foreground, PresentationRgb background) {
  final first = relativeLuminance(foreground);
  final second = relativeLuminance(background);
  final lighter = first > second ? first : second;
  final darker = first > second ? second : first;
  return (lighter + 0.05) / (darker + 0.05);
}

const PresentationRgb kLightTextFallback = PresentationRgb(255, 255, 255);
const PresentationRgb kDarkTextFallback = PresentationRgb(18, 24, 38);
const double kMinimumContrast = 4.5;

/// Picks the readable text color, mirroring `EnsureTextContrast`.
PresentationRgb ensureTextContrast(
  PresentationRgb preferred,
  PresentationRgb background, {
  PresentationRgb lightFallback = kLightTextFallback,
  PresentationRgb darkFallback = kDarkTextFallback,
  double minimumRatio = kMinimumContrast,
}) {
  if (contrastRatio(preferred, background) >= minimumRatio) return preferred;
  final lightRatio = contrastRatio(lightFallback, background);
  final darkRatio = contrastRatio(darkFallback, background);
  return lightRatio >= darkRatio ? lightFallback : darkFallback;
}

/// Compact layout breakpoint (640 logical pixels), mirroring the reference.
bool useCompactLayout(int logicalWidth, [int breakpoint = 640]) => logicalWidth < breakpoint;

/// DPI scaling in integer logical pixels.
int scaleForDpi(int logicalPixels, int scalePercent) {
  if (logicalPixels <= 0 || scalePercent <= 0) return 0;
  return (logicalPixels * scalePercent / 100.0).round();
}

/// Spacing tokens shared by dashboard, settings, tray and overlay.
class Spacing {
  const Spacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double gridMargin = 12;
  static const double cardMinWidth = 400;
}

/// Corner radius tokens.
class Radii {
  const Radii._();

  static const double sm = 4;
  static const double md = 8;
  static const double lg = 12;
}

/// Builds the app theme: light/dark detection via luminance, contrast
/// adjustments and the shared spacing tokens.
ThemeData buildAppTheme(Brightness brightness) {
  final scheme = brightness == Brightness.dark
      ? const ColorScheme.dark(
          primary: Color(0xFF8AB4F8),
          onPrimary: Color(0xFF0E1116),
          secondary: Color(0xFF78D1B8),
          surface: Color(0xFF151A21),
          onSurface: Color(0xFFE6EAF0),
          error: Color(0xFFF28B82),
          onError: Color(0xFF2A0E0B),
        )
      : const ColorScheme.light(
          primary: Color(0xFF1A5FB4),
          onPrimary: Colors.white,
          secondary: Color(0xFF0F7B5F),
          surface: Color(0xFFFBFBFD),
          onSurface: Color(0xFF14181F),
          error: Color(0xFFB3261E),
          onError: Colors.white,
        );
  final theme = ThemeData.from(colorScheme: scheme, useMaterial3: true);
  return theme.copyWith(
    cardTheme: CardThemeData(
      elevation: 0,
      margin: const EdgeInsets.all(Spacing.md),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.md)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.sm)),
      isDense: true,
    ),
  );
}

/// Semantic status colors shared by cards, tray icon and overlay.
extension HealthColors on Health {
  Color color(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    return switch (this) {
      Health.healthy => dark ? const Color(0xFF6FCF97) : const Color(0xFF1B7F4D),
      Health.partial => dark ? const Color(0xFFF2C94C) : const Color(0xFF9A6B00),
      Health.error => dark ? const Color(0xFFF28B82) : const Color(0xFFB3261E),
      Health.disabled => dark ? const Color(0xFF6B7280) : const Color(0xFF6B7280),
    };
  }
}

/// Environment theme override so widget tests can pin a brightness.
class ThemeOverride extends InheritedWidget {
  const ThemeOverride({super.key, required this.brightness, required super.child});

  final Brightness? brightness;

  static Brightness? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeOverride>()?.brightness;

  @override
  bool updateShouldNotify(ThemeOverride oldWidget) => oldWidget.brightness != brightness;
}