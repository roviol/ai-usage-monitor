## ADDED Requirements

### Requirement: Standalone Windows GUI artifact
The Windows Release build MUST produce one x64 GUI executable that starts without a console and requires no separately installed language runtime or project DLL.

#### Scenario: Clean Windows launch
- **WHEN** the Release executable is copied with an empty writable data directory to a supported Windows 10 or 11 x64 user session
- **THEN** it launches the tray UI without requiring Python, Node.js, Java, .NET or Visual C++ Redistributable installation

### Requirement: Reproducible CMake build
The source MUST include CMake presets and pinned dependency versions with integrity checks, and MUST support the verified Visual Studio 2022 C++ workload even when compiler and bundled CMake are not in the global PATH.

#### Scenario: Build from Visual Studio developer environment
- **WHEN** a developer configures the documented Windows Release preset from Visual Studio Developer PowerShell or the bundled CMake path
- **THEN** configuration, compilation, tests and packaging complete with no undocumented SDK dependency

#### Scenario: Dependency source unavailable
- **WHEN** network fetching is disabled but the documented dependency cache is supplied
- **THEN** the build uses the pinned cached sources and verifies their checksums

### Requirement: Windows resource budgets
The Windows Release artifact MUST be at most 15 MiB, MUST use at most 35 MiB working set after 60 seconds idle with the dashboard hidden, MUST average at most 0.2 percent CPU over a 5-minute idle sample, MUST show its tray icon within 750 ms on the reference host and MUST make no network requests between scheduled refreshes.

#### Scenario: Release performance gate
- **WHEN** the packaged binary is measured under the documented reference configuration with providers idle and dashboard hidden
- **THEN** every Windows size, memory, CPU, startup and network budget passes or the release job fails

### Requirement: Separate portable Linux package
The Linux Release build MUST produce an x86_64 AppImage from the shared C++ code, MUST run without a language runtime and MUST degrade to a normal dashboard window with an explanation when the desktop lacks a usable tray protocol.

#### Scenario: Supported Linux desktop
- **WHEN** the AppImage runs on a documented GNOME with AppIndicator or KDE Plasma test image
- **THEN** tray, tooltip-equivalent status, dashboard, configuration and always-on-top behavior pass the platform acceptance tests

#### Scenario: Tray protocol unavailable
- **WHEN** no supported StatusNotifier or AppIndicator host is detected
- **THEN** the application opens or exposes the dashboard normally and explains why resident tray behavior is unavailable

### Requirement: Linux resource budgets
The Linux AppImage MUST be at most 45 MiB and MUST use at most 50 MiB RSS after 60 seconds idle with the dashboard hidden on the reference Linux image.

#### Scenario: Linux release performance gate
- **WHEN** the AppImage is measured in the documented Linux CI image
- **THEN** its package-size and idle-RSS budgets pass or the Linux release job fails

### Requirement: Single-instance behavior
Each user session MUST run at most one monitor instance; launching the artifact again MUST signal the existing process to show its dashboard and then exit.

#### Scenario: Second launch
- **WHEN** the monitor is already resident and the user launches the executable or AppImage again
- **THEN** the existing dashboard is focused and no second scheduler, tray icon or provider refresh loop remains running

### Requirement: Clean portable footprint
The application MUST NOT install a service, driver, browser runtime or machine-wide registry entry, and MUST keep mutable application data within the active data directory or secure OS credential store.

#### Scenario: Remove portable application
- **WHEN** the user exits and deletes the executable or AppImage plus its adjacent data directory
- **THEN** no background service or auto-start entry remains and any per-user fallback data location is discoverable from prior settings documentation
