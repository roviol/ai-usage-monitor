## Context

The current wxWidgets interface is functionally complete but is assembled mostly from default `wxStaticBoxSizer`, `wxStaticText`, `wxGauge` and ungrouped form controls. This exposes platform-native behavior but produces weak hierarchy, inconsistent spacing and an appearance that varies substantially between Windows and wxGTK. The application is a small resident monitor, so any redesign must preserve instant startup, low idle resource use, keyboard accessibility, Windows/Linux portability and the existing provider/scheduler architecture.

## Goals / Non-Goals

**Goals:**

- Establish a coherent modern visual language shared by dashboard and settings.
- Make used quota, status, reset time and errors scannable at a glance.
- Adapt to system light/dark colors and high-DPI scaling.
- Keep native text entry, selection, scrolling and accessibility behavior.
- Preserve current resource budgets and avoid idle rendering work.
- Make visual states deterministic enough for automated UI assertions and screenshot review.

**Non-Goals:**

- Replacing wxWidgets, introducing HTML/CSS, WebView, Electron, Qt or a separate UI runtime.
- Changing provider protocols, metric semantics, persistence schemas, refresh scheduling or tray lifecycle.
- Adding user-selectable themes, arbitrary accent customization or animated data visualization in this change.
- Reproducing platform design systems pixel-for-pixel across Windows and Linux.

## Decisions

### 1. Central semantic theme tokens

Add a small presentation module under `src/ui` that resolves semantic tokens such as canvas, surface, elevated surface, primary/secondary text, border, accent, focus, success, warning and error from `wxSystemSettings`. It will also define DPI-aware spacing, radii and typography roles. Windows and GTK continue to provide the base appearance; contrast correction and deterministic fallbacks prevent mixed or unreadable themes.

This is preferred over scattered literal colors because every state can be updated on a system-color event and verified centrally. A third-party theme library was rejected because it would increase package and integration risk for a small set of required primitives.

### 2. Custom presentation shells with native interactive controls

Provider cards, status pills, semantic notices and percentage tracks will use lightweight buffered custom painting where native widgets cannot provide the required hierarchy. Text fields, choices, list selection, checkboxes, scrolling and dialog semantics remain native wxWidgets controls. Custom interactive surfaces will either wrap a native button or implement standard keyboard activation, accessible names and focus rendering.

This hybrid approach gives the dashboard a deliberate identity without recreating complex input behavior. Styling every control through custom painting was rejected because it would weaken accessibility and platform conventions.

### 3. Provider cards render structured metric rows

Replace the current static-box construction with a reusable provider-card view. Its header contains provider identity and a text-bearing status pill. Percentage windows use a prominent used value and one refined progress track followed by reset/provenance metadata; balances and token totals use equivalent value rows without false percentage visualization. Stale and error information occupies a semantic notice region below retained metrics.

Cards will be rebuilt from snapshots initially, preserving the current simple data flow. Stable helper components and deterministic semantic states leave room for incremental updates later without coupling domain objects to UI concerns.

### 4. Responsive sizer-based layout

Continue using wxSizer ownership and scrolling, but introduce explicit compact and regular breakpoints derived from DPI-adjusted client width. The app bar may wrap secondary actions below the title in compact mode. Settings uses a provider navigation region and a scrollable grouped editor side-by-side at regular width, then stacks them at compact width. No absolute pixel positioning will be introduced.

This approach is portable and testable with synthetic resize events. A fixed larger minimum window was rejected because it would fail on scaling and small displays.

### 5. Theme changes propagate through a presentation context

Top-level windows own or reference the current theme and apply it recursively when the platform reports a system-color change. Custom components repaint, native controls receive compatible foreground/background colors only where needed, and layout is recalculated only if font or DPI metrics changed. Snapshot state and user input remain untouched.

### 6. Visual verification complements behavioral tests

Unit tests will cover token contrast, percentage clamping and compact-layout decisions. UI integration tests will locate controls by accessible label, verify keyboard order and assert content at multiple window sizes. Deterministic fixture snapshots will exercise healthy, refreshing, stale, error, no-data and multiple-quota cards in both theme variants. Screenshot review will be used as a release artifact rather than brittle pixel-perfect equality across platforms.

## Risks / Trade-offs

- [Custom-painted surfaces can diverge across Windows and GTK] → Keep primitives small, use system fonts/colors and maintain platform screenshot baselines for review.
- [Dark-theme detection is inconsistent on older wxGTK environments] → Derive a luminance fallback from system window colors and guarantee contrast-adjusted semantic tokens.
- [Rebuilding cards may flicker during refresh] → Use buffered painting, freeze/thaw around structural rebuilds and update only on delivered snapshots.
- [More generous spacing can reduce information density] → Provide compact layout tokens and keep reset/provenance metadata concise rather than hiding it.
- [Rounded custom visuals may not expose accessibility automatically] → Keep text as real labeled controls where possible and explicitly set names, roles and keyboard behavior for custom components.
- [Visual additions can increase binary size or idle cost] → Use generated vector/path primitives, no new runtime dependency and enforce existing measurement scripts before release.

## Migration Plan

1. Introduce theme tokens and reusable visual primitives behind the existing `DashboardFrame` and `SettingsDialog` interfaces.
2. Migrate dashboard composition and validate all provider states without changing snapshot callbacks.
3. Migrate settings grouping while preserving control IDs, save/test handlers and validation behavior.
4. Add theme, scaling, keyboard and screenshot verification on Windows, then repeat smoke verification on wxGTK.
5. Rebuild portable artifacts and run established size, memory, startup and idle gates.

Rollback is limited to restoring the prior `src/ui` implementation; no settings or cache migration is required because this change introduces no persistent schema changes.

## Open Questions

- Confirm during implementation whether the installed wxWidgets version reports system appearance changes reliably on all selected Linux desktops; otherwise refresh the theme when a window is activated in addition to the system-color event.
- Decide from the first Windows and GTK screenshot pass whether compact settings should fully stack or retain a narrow provider rail, using the no-clipping requirements as the acceptance constraint.
