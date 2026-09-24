## 1. Visual Foundation

- [x] 1.1 Add a `src/ui` presentation module with semantic light, dark and system-fallback color tokens, typography roles and DPI-aware spacing/radius values.
- [x] 1.2 Implement contrast and luminance helpers that guarantee readable semantic text/background pairs and add unit tests for the 4.5:1 normal-text threshold.
- [x] 1.3 Add reusable buffered visual primitives for surfaces, status pills, semantic notices and percentage progress tracks without adding an external UI dependency.
- [x] 1.4 Give every custom primitive accessible names/value descriptions, visible focus treatment and DPI-correct minimum sizing.
- [x] 1.5 Wire top-level windows to re-resolve and apply presentation tokens on system-color and DPI changes without resetting current data or form input.

## 2. Dashboard Modernization

- [x] 2.1 Replace the current toolbar composition with a compact modern app bar containing title, global refresh, settings and always-on-top controls in logical keyboard order.
- [x] 2.2 Implement a reusable provider-card view with provider identity, textual status pill, observation/freshness metadata and theme-aware surface treatment.
- [x] 2.3 Render percentage quota windows as prominent used values with accessible progress tracks and visually associated reset/provenance metadata, omitting remaining-percentage rows.
- [x] 2.4 Render balance, token and unavailable metrics with the same hierarchy without applying misleading percentage visualization.
- [x] 2.5 Add semantic refreshing, stale, no-data and actionable-error treatments that retain cached metrics and do not rely on color alone.
- [x] 2.6 Prevent refresh flicker by buffering painted surfaces and freezing/thawing structural card rebuilds while preserving independent provider completion updates.
- [x] 2.7 Implement regular and compact dashboard layouts so app-bar actions and card content reflow at the supported minimum width and high-DPI scaling.
- [x] 2.8 Restyle the missing-tray fallback as a theme-aware semantic notice while preserving automatic dashboard exposure.

## 3. Settings Modernization

- [x] 3.1 Recompose settings into clearly labeled global-preferences, provider-navigation and scrollable provider-editor regions while preserving existing handlers and control behavior.
- [x] 3.2 Group provider fields into identity, connection, usage mapping and security sections with stable layout when provider-specific fields are hidden.
- [x] 3.3 Style add/remove, connection-test and dialog actions with clear primary, secondary, destructive, disabled, hover and focus states using native activation semantics.
- [x] 3.4 Present validation, connection-test and session-only credential feedback adjacent to the relevant group using accessible semantic notices in both themes.
- [x] 3.5 Implement a compact settings layout and vertical scrolling that keeps every field and action reachable at minimum width and 200 percent scaling.
- [x] 3.6 Verify that switching providers, cancelling, saving, testing connections and opening the data directory preserve their current functional semantics after recomposition.

## 4. Accessibility and Visual Verification

- [x] 4.1 Add deterministic UI fixture states for healthy, refreshing, stale, error, no-data, balance and multiple-quota provider cards.
- [x] 4.2 Add UI assertions for accessible labels, progress values, logical tab order, keyboard activation and non-color status text across dashboard and settings.
- [x] 4.3 Add layout tests at minimum/regular widths and 100, 125, 150 and 200 percent scaling that detect clipping, overlap and unreachable content.
- [ ] 4.4 Capture review screenshots for deterministic light and dark fixture states on Windows and wxGTK, documenting expected platform-native differences.
- [x] 4.5 Verify live system-theme changes repaint visible windows without losing snapshots, settings edits, selection or focus.

## 5. Cross-Platform Release Gates

- [ ] 5.1 Build and run unit, fixture and UI integration tests with warnings as errors on Windows and Linux.
- [x] 5.2 Run keyboard-only and screen-reader-oriented smoke checks on the Windows dashboard and settings window.
- [ ] 5.3 Run GNOME/AppIndicator and KDE Plasma smoke checks for theme colors, compact layout, tray fallback and always-on-top behavior.
- [ ] 5.4 Rebuild the Windows portable package and Linux AppImage and enforce the existing package-size, idle-memory, startup, idle-CPU and between-refresh network gates.
- [x] 5.5 Update user documentation with the refreshed dashboard/settings screenshots and any platform theme limitations discovered during verification.
