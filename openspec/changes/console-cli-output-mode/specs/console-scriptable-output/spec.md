## Purpose

Provides a non-interactive, one-shot console execution mode that fetches current provider usage data, prints it in a script-selectable format, and exits, so the monitor's data can be consumed by shell scripts and other tooling.

## ADDED Requirements

### Requirement: One-shot execution mode
The system MUST support a console invocation that performs a single provider data refresh, prints the resulting snapshot, and terminates the process, without entering the interactive redraw loop, without switching the terminal into raw/no-echo mode, and without waiting for or reading any keypress.

#### Scenario: One-shot flag exits after printing
- **WHEN** the user launches the application with the console one-shot flag
- **THEN** the process refreshes all enabled providers once, prints their snapshot, and exits without waiting for further input

#### Scenario: One-shot mode does not alter terminal state
- **WHEN** one-shot mode runs
- **THEN** the terminal is not put into raw mode and no screen-clearing or cursor-repositioning escape sequences are emitted

#### Scenario: Existing interactive mode unaffected
- **WHEN** the user launches the console dashboard without the one-shot flag
- **THEN** the interactive, continuously-refreshing dashboard starts exactly as before this capability was added

### Requirement: Selectable output format
The system MUST allow the caller to select between a `text` output format and a `json` output format for one-shot mode, defaulting to `text` when no format is specified.

#### Scenario: Text format requested
- **WHEN** one-shot mode runs with the text format selected (or no format specified)
- **THEN** the output is human-readable, showing for each configured provider its name, health/connection state, observation time, and available metrics with their values, units, and reset information where applicable

#### Scenario: JSON format requested
- **WHEN** one-shot mode runs with the JSON format selected
- **THEN** stdout contains a single well-formed JSON document describing every configured provider's snapshot (identity, health state, observation time, metrics with kind/value/unit/availability/provenance/reset data, and any error), and stdout contains no other text

#### Scenario: Unsupported format requested
- **WHEN** one-shot mode runs with a format value that is neither `text` nor `json`
- **THEN** the system reports an error describing the invalid format and exits without printing a snapshot

### Requirement: Shared data source with interactive mode
One-shot mode MUST load the same settings and reuse the same provider construction and refresh logic as interactive console mode, so its output reflects the same configuration, credentials, and provider set without a separate data path.

#### Scenario: Same configuration honored
- **WHEN** one-shot mode and interactive console mode are run against the same settings file
- **THEN** both report the same configured providers and equivalent metric data for a given refresh

### Requirement: Exit status reflects provider health
One-shot mode MUST set the process exit code to indicate whether all enabled providers were successfully refreshed, returning a non-zero exit code when at least one enabled provider ends the run in an error state, and zero otherwise.

#### Scenario: All providers healthy
- **WHEN** one-shot mode completes and every enabled provider has a healthy or partial (non-error) state
- **THEN** the process exits with status code 0

#### Scenario: A provider errored
- **WHEN** one-shot mode completes and at least one enabled provider is in an error state
- **THEN** the process exits with a non-zero status code, and the printed output still includes that provider's error and any cached metrics
