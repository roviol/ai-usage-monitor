## ADDED Requirements

### Requirement: Windows session termination is never vetoed by resident UI behavior
On Windows, the application MUST accept an operating-system request to end the user session for logoff, shutdown, or restart, regardless of dashboard, settings, or overlay visibility. The dashboard's normal close-to-tray behavior MUST NOT veto or delay this system request, and the application MUST NOT display a confirmation prompt.

#### Scenario: Shutdown is requested while the dashboard is hidden
- **WHEN** Windows queries whether the session may end while the application is resident only in the tray
- **THEN** the application allows the session to end without showing a window or requiring user action

#### Scenario: Restart is requested while application windows are visible
- **WHEN** Windows queries whether the session may end while the dashboard, settings dialog, or overlay is visible
- **THEN** the application allows the session to end without applying the dashboard close-to-tray veto

#### Scenario: Another application cancels session termination
- **WHEN** the application has accepted the query but Windows subsequently cancels the session termination
- **THEN** monitoring, tray, dashboard, and overlay behavior continue without requiring application resources to be rebuilt

### Requirement: Confirmed session termination performs non-interactive cleanup
When Windows confirms that the session is ending, the application MUST terminate without waiting for user input or an in-progress provider refresh. Cleanup MUST be idempotent and MUST stop the scheduler and child processes, the single-instance activation watcher, overlay timers and native hooks, the recovery hotkey, and tray ownership before process termination.

#### Scenario: Session ends during a provider refresh
- **WHEN** Windows confirms session termination while a provider refresh or child process is active
- **THEN** the application cancels the work, releases resident resources, and exits without requiring Windows to force-close it

#### Scenario: Cleanup is reached more than once
- **WHEN** explicit-exit and application-exit paths both reach the shared cleanup operation
- **THEN** each resource is stopped at most once and the process exits without deadlock or invalid repeated destruction

### Requirement: Ordinary dashboard close remains resident
Outside an operating-system session termination, closing the dashboard through its window controls MUST hide the dashboard and MUST leave monitoring and the tray icon active.

#### Scenario: User closes the dashboard window
- **WHEN** the user selects the dashboard close control during a normal desktop session
- **THEN** the dashboard is hidden and the application continues monitoring from the tray

### Requirement: Native window titles are stable and non-sensitive
Every native top-level window title owned by the application MUST use a stable, concise application or dialog identity. Titles MUST NOT contain snapshot-derived or user-configurable usage data, including provider names, account labels, quota values, balances, reset times, freshness, or error details.

#### Scenario: Overlay receives updated usage snapshots
- **WHEN** the overlay projection changes after initial data, refresh, countdown, stale data, or an error
- **THEN** its native title remains the concise application title and contains none of the projected values or status text

#### Scenario: Windows identifies the application during shutdown
- **WHEN** Windows displays the native title of an application window while ending the session
- **THEN** the displayed text identifies AI Usage Monitor without exposing usage or account data

### Requirement: Dynamic usage remains available outside the native title
Removing dynamic data from native window titles MUST NOT remove it from the overlay's visible content or its unlocked accessible description. The dashboard and tray MUST remain the textual equivalents when the overlay is locked or non-activating.

#### Scenario: Accessible overlay is unlocked
- **WHEN** usage snapshots are shown while the overlay is unlocked
- **THEN** the overlay retains a concise accessible name and a current description of the visible usage while its native title remains static

#### Scenario: Overlay is locked
- **WHEN** the overlay is locked and click-through
- **THEN** the same usage and status information remains available through the dashboard or tray without being copied into the native title
