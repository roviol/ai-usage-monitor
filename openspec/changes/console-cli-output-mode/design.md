## Context

`RunConsoleDashboard` (`src/console/console_dashboard.cpp:350`) currently does setup (paths, settings, providers, scheduler, cache) and then unconditionally enters a blocking interactive loop: raw terminal mode, signal handlers, keypress polling, and a 1s redraw using ANSI screen-clear + `RenderDashboard`. There is no serializer for `ProviderSnapshot`/`Metric` today; JSON usage elsewhere in the codebase is for settings/provider API payloads only (`src/config.cpp`, `src/providers.cpp`). See proposal.md for motivation.

## Goals / Non-Goals

**Goals:**
- Add flags to `--console` invocation: a one-shot trigger and a format selector (`text`/`json`).
- Factor the existing setup + "refresh once, build ordered snapshot vector" logic out of the interactive loop so both modes call it.
- Add a JSON serializer for the snapshot data reusing existing enum-to-string helpers (`ToString`, `FormatMetric`, `FormatResetMetadata`) where possible.
- Keep `--console` alone behaving exactly as before (backward compatible default).

**Non-Goals:**
- No changes to desktop/tray mode, provider fetching logic, settings schema, or cache format.
- No new CLI argument parsing framework — this stays consistent with the existing minimal `argv` scan in `app.cpp`.
- No streaming/watch-multiple-times mode beyond the existing interactive loop; one-shot is strictly single-pass.

## Decisions

**Flag shape**: `--console --once [--format text|json]`. `--once` gates the new code path; `--format` only has meaning combined with `--once` (interactive mode keeps its own hardcoded ANSI renderer). Rationale: minimal surface change, no risk to existing `--console` usage since `--once` is additive and opt-in. Alternative considered — a single `--console=once:json` composite flag — rejected as harder to parse and inconsistent with the existing plain-flag style.

**Reuse via extraction**: extract the block in `RunConsoleDashboard` that resolves paths, loads settings, builds providers, runs `scheduler.RefreshAll()` synchronously (blocking until first results are in, not just triggered), and materializes the ordered `vector<ProviderSnapshot>` into a helper (e.g. `FetchSnapshotsOnce`). Both `RunConsoleDashboard`'s interactive loop (first frame) and the new one-shot path call it. Rationale: satisfies the "shared data source" requirement without duplicating provider construction. Alternative — spawn interactive mode internally and capture its first frame — rejected as heavier and still requiring the terminal/raw-mode side effects the spec says one-shot must avoid.

Note: `RefreshScheduler::RefreshAll()` as used today triggers async refresh and results arrive via callback (interactive mode just waits for the next redraw tick). One-shot mode needs to block until all enabled providers have reported once (or a bounded timeout elapses) before printing, since there is no redraw loop to eventually catch late results. This requires a wait/condition mechanism (e.g. condition variable signaled by the snapshot callback, counting enabled providers) — a small addition, not a scheduler redesign.

**Text format in one-shot mode**: reuse `RenderDashboard`/`RenderProviderSection` (same ANSI box output as interactive mode) rather than inventing a second plain-text layout, so the two modes stay visually consistent and there's one rendering path to maintain.

**JSON serialization**: hand-write a small `SnapshotsToJson(const std::vector<ProviderSnapshot>&)` using the same JSON library already linked in the project (used in `config.cpp`/`providers.cpp`), producing one array of provider objects with fields: `providerId`, `displayName`, `kind`, `health`, `freshness`, `observedAt` (ISO 8601), `accountLabel`, `metrics[]` (`kind`, `label`, `value`, `unit`, `availability`, `provenance`, `resetsAt`, `window`), and `error` (`code`, `message`, `retryable`) when present. Rationale: matches domain.h fields 1:1, keeps output stable and easy for `jq` consumers; avoids reusing display-oriented helpers like `HealthLabel`/`FormatMetric` which embed ANSI codes and localized Spanish text unsuitable for machine consumption.

**Exit code**: after building the ordered snapshot vector, compute non-zero exit if any snapshot with a corresponding enabled provider config has `Health::Error`. Rationale: mirrors interactive mode's own error concept (`Health::Error`) with no new health model.

## Risks / Trade-offs

[Blocking wait for all providers could hang if a provider never calls back] → bound the wait with a timeout (e.g. the provider's own request timeout plus margin, or a fixed ceiling like 30s); providers that haven't reported by then are included using their last cached snapshot (same fallback the interactive loop already uses for "no data yet").

[JSON schema becomes a de-facto public contract once scripts depend on it] → keep field names identical to internal domain enums/fields (traceable, low churn) and document the shape in the spec's scenarios; no versioning added now since this is a new capability, but future breaking changes should consider a `--format json` version bump if needed later.

[Duplication risk between `RenderDashboard`'s first-frame use and one-shot's use of the same function] → both call sites already need the same box-drawing renderer; no behavior fork required beyond skipping the ANSI clear-screen sequence for one-shot (small conditional in the caller, not in `RenderDashboard` itself — one-shot can call `RenderProviderSection` directly instead of `RenderDashboard`'s screen-clearing wrapper, or a trimmed variant without `\x1b[2J\x1b[H`).
