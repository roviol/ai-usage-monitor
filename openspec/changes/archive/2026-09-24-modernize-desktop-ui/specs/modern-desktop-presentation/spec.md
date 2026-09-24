## ADDED Requirements

### Requirement: Cohesive adaptive visual system
The desktop UI MUST apply one shared set of semantic colors, typography roles, spacing values, corner treatments and control states across the dashboard and settings window. The palette MUST adapt to the operating-system light or dark appearance and MUST refresh when the system color scheme changes.

#### Scenario: Application opens in light appearance
- **WHEN** the application creates its windows while the operating system uses a light appearance
- **THEN** the dashboard and settings use the shared light surface, text, border, accent and semantic-status tokens consistently

#### Scenario: System changes to dark appearance
- **WHEN** the operating-system appearance changes from light to dark while the application is running
- **THEN** visible application windows repaint with the dark token set without restart or loss of state

#### Scenario: Theme information is unavailable
- **WHEN** the platform cannot report a reliable light or dark appearance
- **THEN** the application uses readable system-derived fallback colors instead of an incomplete or mixed palette

### Requirement: Modern scannable dashboard hierarchy
The dashboard MUST present a compact application bar and a visually separated card for each provider. Each card MUST prioritize provider identity, status, used value and progress, while displaying observation time, reset time, provenance and actionable errors as secondary information without restoring a separate remaining-percentage row.

#### Scenario: Healthy percentage provider
- **WHEN** a provider has a fresh available used-percentage metric
- **THEN** its card shows the provider name, a healthy status badge, a prominent used value, an accessible progress bar and its reset metadata in a clear hierarchy

#### Scenario: Provider has multiple quota windows
- **WHEN** Claude or Codex reports more than one percentage quota window
- **THEN** each used value and its own reset time remain visually associated inside the same provider card

#### Scenario: Provider refresh fails with cached data
- **WHEN** a provider has an actionable error and retained stale metrics
- **THEN** the card distinguishes the stale values from a visible error treatment without relying on color alone

#### Scenario: Global refresh is active
- **WHEN** the user invokes the single global refresh action
- **THEN** the app bar and independently updating cards communicate progress without blocking, flashing the entire layout or creating per-provider refresh buttons

### Requirement: Structured modern settings experience
The settings window MUST separate global preferences, provider selection and provider-specific fields into clearly labeled regions. Related fields MUST be grouped, optional or advanced fields MUST be visually distinguishable, and validation or connection-test feedback MUST appear adjacent to the affected configuration without obscuring other controls.

#### Scenario: User selects a provider
- **WHEN** the user selects a provider from the provider region
- **THEN** the editor presents its identity, connection and security controls in stable labeled groups with irrelevant fields hidden

#### Scenario: Validation fails
- **WHEN** the user enters an invalid executable, URL, mapping or refresh interval
- **THEN** the affected region displays an accessible error message and preserves the entered values for correction

#### Scenario: Secret Service is unavailable
- **WHEN** secure persistent storage is unavailable for an HTTP provider
- **THEN** the security group presents the session-only explanation as a visible semantic notice that remains readable in both themes

### Requirement: Responsive high-DPI layout
The dashboard and settings window MUST reflow at their documented minimum widths and at 100, 125, 150 and 200 percent display scaling. Primary information and actions MUST remain visible without horizontal clipping, while vertically overflowing content MUST remain reachable by scrolling.

#### Scenario: Narrow dashboard
- **WHEN** the dashboard is resized to its minimum supported width
- **THEN** app-bar actions and provider-card content reflow while provider names, used values, reset information and global refresh remain usable

#### Scenario: Settings at 200 percent scaling
- **WHEN** the settings window is displayed at 200 percent scaling
- **THEN** labels and fields remain legible, controls do not overlap and all configuration regions are reachable using scrolling

### Requirement: Accessible interaction states
Every actionable or status-bearing visual element MUST expose a readable label, keyboard focus, disabled state and non-color status cue. Custom-drawn controls MUST preserve native keyboard activation and accessibility metadata, and custom text/background pairs MUST meet at least 4.5:1 contrast for normal text.

#### Scenario: Keyboard-only navigation
- **WHEN** the user navigates the dashboard or settings without a pointing device
- **THEN** focus follows a logical order, remains visibly indicated and can activate refresh, settings, provider management and dialog actions

#### Scenario: Color distinction is unavailable
- **WHEN** a user cannot distinguish the healthy, partial and error colors
- **THEN** status text or symbols still identify each state and progress retains an accessible value description

### Requirement: Lightweight native rendering
The modern presentation MUST remain implemented with wxWidgets and code-native assets, MUST NOT add a browser engine or external UI runtime, and MUST avoid continuous animation or repaint timers while the application is idle.

#### Scenario: Dashboard is idle
- **WHEN** no refresh, resize or theme event is occurring
- **THEN** the presentation layer performs no periodic animation repaint and introduces no network activity

#### Scenario: Portable package is built
- **WHEN** the Windows and Linux portable artifacts are produced after the visual redesign
- **THEN** they continue to satisfy the established platform package-size and idle-memory release gates
