## ADDED Requirements

### Requirement: Resident tray lifecycle
The system MUST start without a console, create one status icon, keep the dashboard hidden initially and remain resident when the dashboard is closed.

#### Scenario: Normal startup
- **WHEN** the user launches the executable
- **THEN** one tray icon appears and no dashboard or terminal window is forced open

#### Scenario: Dashboard close button
- **WHEN** the user closes the dashboard window
- **THEN** the window is hidden and monitoring continues in the tray

### Requirement: Status icon and tooltip
The tray icon MUST distinguish healthy, stale or partial, error or authentication, and disabled or no-data states. Its tooltip MUST summarize the highest-priority provider information and freshness within the platform length limit.

#### Scenario: All enabled providers healthy
- **WHEN** all enabled providers have fresh successful snapshots
- **THEN** the icon shows the healthy state and the tooltip includes compact current metrics or reset information

#### Scenario: Tooltip exceeds Windows capacity
- **WHEN** the full summary would exceed 127 characters
- **THEN** the tooltip uses a deterministic prioritized summary that fits and still indicates overall status or freshness

#### Scenario: One provider becomes stale
- **WHEN** any enabled provider retains stale data after a failed refresh
- **THEN** the aggregate icon is not healthy and the tooltip identifies stale or error status

### Requirement: Single dashboard window
A primary click on the tray icon MUST open or focus one dashboard window containing a card for each configured provider, and repeated clicks MUST NOT create duplicate windows.

#### Scenario: First tray click
- **WHEN** the dashboard is hidden and the user clicks the tray icon
- **THEN** the dashboard becomes visible and focused

#### Scenario: Click while dashboard is open
- **WHEN** the dashboard already exists and the user clicks the tray icon
- **THEN** the same window is focused without creating a second instance

### Requirement: Clear provider cards
Each provider card MUST show provider name, connection state, observation time, available usage or balance metrics, reset times and metric provenance where ambiguity exists. Errors MUST be actionable and MUST NOT erase the last valid stale data.

For percentage-based quota windows, the dashboard MUST show only the used percentage and MUST omit the complementary remaining percentage to keep cards compact.

#### Scenario: Partial metric coverage
- **WHEN** a provider is reachable but does not expose a remaining quota
- **THEN** its card shows available metrics and explicitly labels remaining quota as unavailable

#### Scenario: Cached data after error
- **WHEN** a provider currently fails but has a prior valid snapshot
- **THEN** its card shows the error, stale indicator, old observation time and cached metrics together

#### Scenario: Used and remaining percentages are available
- **WHEN** a provider snapshot contains complementary used and remaining percentages for the same quota window
- **THEN** its card shows the used value and progress bar only, without a separate remaining row

### Requirement: Manual refresh feedback
The dashboard MUST provide one global refresh control in its top toolbar and MUST display progress without blocking window interaction. Provider cards MUST NOT contain individual refresh controls.

#### Scenario: User refreshes all
- **WHEN** the user activates `Refrescar todo`
- **THEN** enabled providers enter a visible refreshing state and cards update independently as results arrive

### Requirement: Persistent always-on-top mode
The dashboard MUST provide an always-on-top toggle, persist its value and apply it immediately without restarting monitoring. The default MUST be off.

#### Scenario: Enable always on top
- **WHEN** the user enables `Siempre visible`
- **THEN** the existing dashboard remains above normal windows and the setting is restored on next launch

#### Scenario: Disable always on top
- **WHEN** the user disables `Siempre visible`
- **THEN** the dashboard immediately returns to normal window ordering

### Requirement: Explicit exit and tray recovery
The tray menu MUST provide dashboard, refresh, settings and exit actions. Exit MUST stop timers and child processes and remove the tray icon; the application MUST recreate the icon after the Windows shell restarts.

#### Scenario: Exit from tray
- **WHEN** the user chooses `Salir`
- **THEN** active operations are cancelled within their timeout, persisted state is flushed and the process terminates without an orphan tray icon or child process

#### Scenario: Explorer restarts
- **WHEN** Windows broadcasts taskbar recreation while the application is running
- **THEN** the application registers its tray icon again without starting a second monitor instance
