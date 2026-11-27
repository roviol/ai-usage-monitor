## Purpose

Define how functional parity between the Flutter application and the C++ reference application is demonstrated, so that "same functionality" is verified with evidence rather than asserted, and both applications can be compared side by side.

## ADDED Requirements

### Requirement: Provider parsing parity against fixtures
The Flutter application SHALL be tested against the same provider response fixtures used by the reference test suite (Codex JSONL, Claude usage text, DeepSeek balance, generic usage, Ollama status, account and cloud usage), and each parse MUST produce the same normalized snapshots, metrics and errors as the reference for the same input.

#### Scenario: Fixture produces identical snapshot
- **WHEN** a response fixture is parsed by both applications
- **THEN** the resulting snapshot matches on provider id, metrics, values, units, scopes, provenances, availabilities, labels, reset times, health and error

#### Scenario: Malformed fixture fails identically
- **WHEN** an invalid fixture is parsed
- **THEN** both applications reject it with the same error code and message and produce no synthesized metrics

### Requirement: Decimal and domain logic parity
The Flutter application SHALL implement the same decimal string arithmetic, metric aggregation and health aggregation behavior as the reference, producing identical values for the same inputs, including derived percentages and spends.

#### Scenario: Derived values match
- **WHEN** a remaining percentage or derived spend is computed
- **THEN** the Flutter result is the exact same decimal string as the reference

#### Scenario: Aggregation rules match
- **WHEN** metrics or snapshots are aggregated
- **THEN** the Flutter application applies the same matching, summation and health-precedence rules as the reference

### Requirement: Persistence round-trip parity
Settings and cache written by either application SHALL be readable by the other without loss, and a round trip through the Flutter application MUST NOT change the meaning of any field.

#### Scenario: Cross-application round trip
- **WHEN** a settings or cache file is written by one application and loaded and re-saved by the other
- **THEN** the configuration and snapshots are preserved with identical meaning and no unknown fields are introduced

#### Scenario: Redacted export matches
- **WHEN** settings are exported with credentials redacted
- **THEN** protected values are replaced with the same redaction marker as the reference

### Requirement: Presentation text parity
The Flutter application SHALL produce the same functional text for status tooltips, provider health and freshness labels, provenance labels, error notices, overlay row values, countdowns and additional-count summaries as the reference, so equivalent states read the same even if their styling differs.

#### Scenario: Tooltip text matches
- **WHEN** the same snapshots are summarized
- **THEN** the tray tooltip presents the same aggregate status, per-provider state and data age as the reference

#### Scenario: Countdown text matches
- **WHEN** a reset time is formatted at a given moment
- **THEN** the countdown text matches the reference format for the same remaining duration

#### Scenario: Overlay projection matches
- **WHEN** the same snapshots are projected into overlay rows
- **THEN** the visible rows, values, labels, statuses and hidden count match the reference

### Requirement: Reference application remains available
The C++ application SHALL remain buildable and runnable alongside the Flutter application so that both can be launched against the same configuration and data for manual comparison.

#### Scenario: Both applications run together
- **WHEN** the user builds and runs both applications pointing at the same data directory
- **THEN** each displays the same providers, metrics and status for the same refresh results

#### Scenario: Parity harness reports a difference
- **WHEN** the comparison harness detects a difference between the applications
- **THEN** it reports the differing field, provider and input so the difference can be resolved before the C++ application is retired
