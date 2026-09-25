# console-dashboard Specification

## Purpose

Provides a text-only, terminal-rendered view of AI usage across configured providers for Linux users who run the monitor without a graphical desktop session, showing the same status, quotas, progress, and reset information as the desktop dashboard.

## Requirements

### Requirement: Console-only launch mode
The system MUST support launching in a text-mode console dashboard on Linux that never creates a tray icon, system notification, or GUI window, and that runs entirely within the invoking terminal.

#### Scenario: User launches console mode
- **WHEN** the user starts the application in console mode on Linux
- **THEN** no tray icon or GUI window is created and the terminal displays the text dashboard

#### Scenario: Console mode uses existing configuration
- **WHEN** console mode starts and a settings file already exists from the desktop mode
- **THEN** the same providers, credentials, and preferences are loaded and monitored without requiring separate setup

### Requirement: Full-provider text dashboard
The console dashboard MUST render one section per configured provider showing the same information as a desktop provider card: provider name, connection/health state, observation time and freshness, available usage or balance metrics, and metric provenance where ambiguity exists. Errors MUST be shown inline and MUST NOT discard the last valid cached metrics.

#### Scenario: Healthy provider rendering
- **WHEN** a provider has a fresh successful snapshot
- **THEN** its section shows the provider name, a healthy status marker, the observation time, and its current metrics

#### Scenario: Stale data after a failed refresh
- **WHEN** a provider's last refresh failed but a prior valid snapshot exists
- **THEN** its section shows the error message, a stale indicator, the old observation time, and the cached metrics together

#### Scenario: Partial metric coverage
- **WHEN** a provider is reachable but does not expose a remaining quota
- **THEN** its section shows the available metrics and explicitly labels the missing quota as unavailable

### Requirement: Text-based usage progress bars
For each percentage-based quota metric, the console dashboard MUST render a text progress bar (e.g. filled/empty characters) reflecting the used percentage, alongside the numeric value, and MUST omit the complementary remaining-percentage figure.

#### Scenario: Percentage metric rendering
- **WHEN** a provider snapshot includes a used-percentage metric
- **THEN** the console output shows a proportional text progress bar and the numeric used percentage for that metric

### Requirement: Reset time and countdown display
The console dashboard MUST show, for every metric that has a reset time, the same reset timestamp and countdown wording used by the desktop dashboard, expressed in the local system timezone.

#### Scenario: Metric with upcoming reset
- **WHEN** a metric has a future reset time
- **THEN** the console output shows the reset time and a countdown to that reset

#### Scenario: Metric reset already elapsed
- **WHEN** a metric's reset time has already passed but no new snapshot has arrived
- **THEN** the console output shows the reset as elapsed rather than a stale countdown

### Requirement: Manual and automatic refresh in the terminal
The console dashboard MUST refresh provider data automatically on the same schedule as the desktop dashboard and MUST provide a keyboard command to trigger an immediate manual refresh of all enabled providers, redrawing sections independently as results arrive.

#### Scenario: Automatic refresh
- **WHEN** the scheduled refresh interval elapses
- **THEN** enabled providers are polled again and the terminal display updates with new data

#### Scenario: Manual refresh key
- **WHEN** the user presses the manual refresh key
- **THEN** all enabled providers are polled immediately and their sections update as results arrive

### Requirement: Graceful terminal exit
The console dashboard MUST provide a keyboard command to exit cleanly, stopping timers and any child processes and leaving no orphaned background monitoring process.

#### Scenario: User quits console mode
- **WHEN** the user presses the quit key
- **THEN** active operations are cancelled within their timeout, persisted state is flushed, and the process terminates
