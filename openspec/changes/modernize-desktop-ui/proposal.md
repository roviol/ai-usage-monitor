## Why

The current dashboard and settings window expose the required information, but their default control layout, dense text treatment and weak visual hierarchy make the application feel dated and harder to scan. A cohesive modern presentation will make quota status, refresh state and configuration easier to understand without sacrificing the small native desktop footprint.

## What Changes

- Introduce a shared visual system for color, typography, spacing, corner treatment, focus states and high-DPI sizing across the dashboard and settings window.
- Redesign the dashboard around a compact app bar, visually distinct provider cards, status badges, prominent used values, refined progress bars and clearer reset/error metadata.
- Modernize settings with better grouping, section hierarchy, field descriptions, validation presentation and primary/secondary action styling.
- Support system light and dark appearance with accessible contrast, while preserving readable fallback colors when theme information is unavailable.
- Add responsive layout behavior for narrow windows and larger display scaling without clipping metrics or actions.
- Preserve native wxWidgets lifecycle, tray behavior, keyboard navigation, low idle resource usage and the existing provider data model.

## Capabilities

### New Capabilities

- `modern-desktop-presentation`: Defines the shared visual language, theme behavior, modern dashboard cards, settings presentation, responsive layout and accessible interaction states.

### Modified Capabilities

None.

## Impact

- Affects the wxWidgets UI implementation in `src/ui`, including dashboard, settings and reusable presentation helpers.
- Adds lightweight code-native visual assets or custom-painted controls where native controls cannot express the required hierarchy.
- Extends UI and visual-regression verification for light/dark appearance, scaling, keyboard focus, compact layouts and provider states.
- Does not change provider protocols, credential handling, scheduling, cache schemas, tray lifecycle or require a browser engine or external language runtime.
