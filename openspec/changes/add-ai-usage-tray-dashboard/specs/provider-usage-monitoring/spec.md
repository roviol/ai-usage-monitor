## ADDED Requirements

### Requirement: Normalized provider snapshots
The system MUST represent each provider result as a timestamped snapshot whose metrics include value, unit, scope, provenance and reset time when applicable, and MUST represent missing data as an explicit availability state rather than numeric zero.

#### Scenario: Provider returns only a balance
- **WHEN** DeepSeek returns a monetary balance without a usage total
- **THEN** the snapshot contains the reported balance and marks used amount as unsupported

#### Scenario: Derived consumption
- **WHEN** a user-defined budget and a provider-reported balance permit calculation of consumed amount
- **THEN** the system labels the consumed amount as derived and does not label it provider-reported

### Requirement: Codex usage integration
The system MUST obtain Codex account, rate-limit and token-activity data through the installed Codex app-server public protocol without reading or copying Codex authentication tokens.

#### Scenario: Authenticated ChatGPT Codex account
- **WHEN** app-server returns one or more rate-limit windows and token activity
- **THEN** the dashboard snapshot contains every supported window, used percentage, reset time and returned token summaries

#### Scenario: Codex authentication is unavailable
- **WHEN** app-server reports no usable account or an authentication error
- **THEN** Codex is marked unauthorized with an actionable message and no previous metric is presented as current

### Requirement: Non-interactive local Claude usage integration
The system MUST obtain Claude subscription usage exclusively by executing the installed client as `claude /usage` with redirected output, no stdin and no pseudo-terminal. It MUST NOT call the Anthropic Usage & Cost API directly or submit a model prompt solely to discover quota.

#### Scenario: Recognized non-interactive Claude output
- **WHEN** the installed Claude client produces recognized session or weekly percentage lines for `claude /usage`
- **THEN** the system extracts those quota windows and each recognized next-reset time, marks their source as CLI bridge and closes the hidden child process

#### Scenario: Unrecognized Claude output
- **WHEN** the redirected command output does not match a tested parser fixture
- **THEN** the system reports subscription quota as unsupported, retains diagnostics without secrets and does not guess values

### Requirement: DeepSeek and OpenAI-compatible monitoring
The system MUST include a DeepSeek preset for its documented balance route and MUST permit generic OpenAI-compatible providers to define optional usage or balance routes and JSON Pointer mappings without assuming that billing routes exist.

#### Scenario: DeepSeek balance refresh
- **WHEN** valid DeepSeek credentials are configured and `/user/balance` succeeds
- **THEN** all returned currency balances and availability state are normalized into the provider snapshot

#### Scenario: Inference-compatible endpoint without billing API
- **WHEN** `/models` succeeds but no usage or balance mapping is configured
- **THEN** the provider is shown as reachable and its financial and quota metrics are marked unsupported

#### Scenario: Invalid custom mapping
- **WHEN** a configured JSON Pointer is absent or resolves to a value of the wrong type
- **THEN** the refresh fails validation for that metric without crashing or interpreting another field

### Requirement: Scheduled and manual refresh
The system MUST refresh enabled providers every 5 minutes by default, MUST allow intervals from 1 through 60 minutes, MUST coalesce overlapping refresh requests and MUST offer a manual refresh.

#### Scenario: Default background operation
- **WHEN** the application runs with default settings
- **THEN** each enabled provider is refreshed no more frequently than once every 5 minutes except for explicit manual refresh

#### Scenario: Manual refresh while refresh is active
- **WHEN** the user requests refresh for a provider whose request is already running
- **THEN** the system reuses or queues at most one refresh and does not start a duplicate concurrent request

### Requirement: Timeouts, backoff and stale cache
The system MUST time out a provider attempt after 10 seconds, apply bounded exponential backoff with jitter for transient failures, honor valid `Retry-After`, and retain the last valid snapshot as stale data with its original timestamp.

#### Scenario: Transient network failure after valid data
- **WHEN** a refresh times out after the provider previously returned valid data
- **THEN** the last valid metrics remain visible as stale alongside the current error and original observation time

#### Scenario: Rate-limited provider
- **WHEN** a provider responds with a retry interval
- **THEN** automatic refresh does not contact that provider before the permitted time

### Requirement: Honest aggregation
The system MUST compute tray and dashboard states from current availability and freshness and MUST NOT add unlike units, scopes or provider-reported and derived values into a misleading total.

#### Scenario: Mixed provider metrics
- **WHEN** Codex exposes rolling percentage, Claude exposes daily tokens and DeepSeek exposes USD balance
- **THEN** the application presents separate labeled metrics and no combined “total tokens remaining” value
