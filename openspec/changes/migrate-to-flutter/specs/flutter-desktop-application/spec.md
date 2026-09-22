## Purpose

Define the shell, dashboard, settings and system tray behavior of the Flutter desktop application so that a user can monitor and configure providers exactly as in the C++ reference application, allowing the visual presentation to differ while the function, status text and data shown remain equivalent.

## ADDED Requirements

### Requirement: Desktop startup and single instance
The Flutter application SHALL start as a desktop application on Windows and Linux, resolve its data location, load settings and cache, and enforce a single running instance: a second launch MUST activate the existing instance instead of starting a new one and then exit.

#### Scenario: Second launch activates the first
- **WHEN** the application is already running and the user launches it again
- **THEN** the existing instance opens its dashboard and the second process exits

#### Scenario: First run opens configuration
- **WHEN** the application starts for the first time without a settings file
- **THEN** it opens the settings window

#### Scenario: Cached data is shown before refreshing
- **WHEN** the application starts with cached snapshots
- **THEN** the dashboard shows them as stale until the first refresh completes

### Requirement: First-run provider defaults
The Flutter application SHALL, when no providers are configured, add Codex if the `codex` executable is discovered, add Claude if `claude` is discovered, and always add a disabled DeepSeek provider with the reference defaults, then persist the result.

#### Scenario: Discovered clients are enabled
- **WHEN** `codex` and `claude` are discovered on the first run
- **THEN** enabled Codex and Claude providers plus a disabled DeepSeek provider are created

#### Scenario: No clients are discovered
- **WHEN** neither client is found
- **THEN** only the disabled DeepSeek provider is created

### Requirement: Dashboard window and provider cards
The Flutter application SHALL provide a dashboard listing every configured provider in configuration order, showing for each: display name, a health status, observation time and freshness, account label when present, its metrics with values and labels, a progress bar for percentage quotas, reset information and the provider error notice. It MUST NOT show value kinds the reference omits from cards (remaining-percentage rows, per-model memory and request counts).

#### Scenario: Provider is healthy
- **WHEN** a provider has fresh metrics
- **THEN** the card shows a connected status, the observation time, the metrics and any reset time

#### Scenario: Provider is disabled
- **WHEN** a provider is disabled
- **THEN** the card shows a disabled status without an error notice

#### Scenario: Provider has no displayable metrics
- **WHEN** every metric is filtered out by the reference card rules
- **THEN** the card shows a metrics-not-available notice

#### Scenario: Provider is refreshing
- **WHEN** a refresh is in progress
- **THEN** the card shows the refreshing notice in the accent style rather than an error

### Requirement: Responsive dashboard grid
The Flutter application SHALL lay out provider cards in a responsive grid that uses available horizontal space: it SHALL add columns as usable width grows based on a minimum cell width of 400 logical pixels with 12-pixel margins, SHALL keep at least one column, and SHALL revert to a single readable column at compact widths without clipping content or adding unnecessary scroll.

#### Scenario: Wide window
- **WHEN** the window is wide enough for several 400-pixel cells and there are enough cards
- **THEN** the dashboard shows multiple columns instead of stacking all cards

#### Scenario: Compact window
- **WHEN** the window is reduced to compact width
- **THEN** the dashboard returns to a single readable column without clipping card content

#### Scenario: Cards fit without scrolling
- **WHEN** all cards fit inside the visible area
- **THEN** the dashboard does not present unnecessary scroll

### Requirement: Always-visible and close-to-tray behavior
The Flutter application SHALL provide a persistent "always visible" dashboard preference independent of background operation, and closing the dashboard window SHALL hide it to the tray rather than exiting, while the tray remains able to reopen it. On Windows, ending the user session MUST NOT be blocked by this close-to-tray behavior.

#### Scenario: Window is closed
- **WHEN** the user closes the dashboard window normally
- **THEN** the window hides and the application keeps running in the tray

#### Scenario: Always-visible is toggled
- **WHEN** the user enables "always visible"
- **THEN** the dashboard stays above normal windows and the preference persists across launches

#### Scenario: Session is ending on Windows
- **WHEN** Windows ends the user session
- **THEN** the application shuts down cleanly instead of vetoing the session end

### Requirement: System tray status
The Flutter application SHALL present a tray icon whose color reflects the aggregated health of all providers and whose tooltip summarizes provider status and data age. Its menu SHALL offer opening the dashboard, refreshing all providers, overlay visibility and lock items when applicable, opening configuration and exiting. When no compatible tray is available, the dashboard SHALL remain usable and show a warning notice.

#### Scenario: Aggregate health changes
- **WHEN** provider health changes between healthy, partial, error and disabled
- **THEN** the tray icon color and tooltip update to the matching aggregate state

#### Scenario: Tray menu actions
- **WHEN** the user selects a tray menu item
- **THEN** the corresponding action runs without opening the dashboard first

#### Scenario: No tray is available
- **WHEN** the desktop offers no compatible tray
- **THEN** the dashboard remains available as a normal window and a tray-unavailable notice is shown

### Requirement: Provider configuration interface
The Flutter application SHALL provide a settings interface that lists providers, allows adding, editing, removing, enabling/disabling, testing, and forgetting credentials, exposes only the fields relevant to each provider kind, and lets the user edit global preferences (refresh interval, always visible), overlay preferences and open the data folder.

#### Scenario: Adding a provider
- **WHEN** the user selects a provider kind and adds it
- **THEN** a provider is created with the kind defaults, a generated identifier and the kind's display name, and is left disabled

#### Scenario: Field visibility per kind
- **WHEN** the user selects a provider kind
- **THEN** only the executable fields for local providers or the URL, credential, route and budget fields for HTTP providers are shown

#### Scenario: Connection test
- **WHEN** the user tests a provider connection
- **THEN** the result message is shown with success or error styling, includes the capability detail when available, and never exposes credential material

#### Scenario: Settings are cancelled
- **WHEN** the user cancels the settings window
- **THEN** no changes are applied and the previous configuration is preserved

### Requirement: Equivalent status language
The Flutter application SHALL present the same functional status information as the reference using equivalent Spanish text for health, freshness, provenance, error notices, overlay counts and reset countdowns; the exact visual styling may differ but every color-coded state MUST retain a text equivalent.

#### Scenario: Health is color-coded
- **WHEN** a provider health is shown with a color
- **THEN** a text label identifies the same state

#### Scenario: Metric provenance is shown
- **WHEN** a metric is not provider-reported
- **THEN** a text label identifies whether it was derived, observed locally or obtained from a local CLI

### Requirement: Theme handling
The Flutter application SHALL follow the system light or dark theme, apply a consistent, readable color scheme with sufficient contrast for text, and reorganize header and settings content at compact widths. Theme changes MUST NOT alter the data shown or the refresh behavior.

#### Scenario: System theme changes
- **WHEN** the system switches between light and dark
- **THEN** the dashboard and settings remain readable and all data stays unchanged

#### Scenario: Compact settings layout
- **WHEN** the settings window is narrow
- **THEN** the provider navigation and editor stack vertically without clipping
