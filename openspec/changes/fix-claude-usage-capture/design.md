## Context

See proposal.md. Local reproduction on 2026-11-24: Claude 2.1.317 reports `loggedIn: false`, `authMethod: none`; `/usage` exits zero with session cost/token totals and no subscription percentages. The stored last successful quota is from 2026-11-23. This does not establish a CLI format regression for authenticated accounts.

## Goals / Non-Goals

**Goals:** Explain how to restore login; preserve successful capture and stale values; prevent session token/cost totals being mistaken for subscription quotas.

**Non-Goals:** Read private credential files, perform OAuth on the user's behalf, use a PTY, call Anthropic directly, or invent subscription usage.

## Decisions

Run `auth status --json` first and use only public boolean/method fields. A structured logged-out response is authoritative even with a nonzero exit code. A structured API-key account reports subscription quotas unsupported. Old clients without this public command fall back to the existing `/usage` path. Malformed successful auth responses fail closed with an actionable diagnostic. Cancellation and a single ten-second deadline cover both subprocesses. Do not include raw auth or usage output in errors.

Keep the successful parser unchanged because authenticated output has not yet been shown to change. Use typed provider errors for unauthorized and unsupported states. Preserve the scheduler's existing stale-cache handling.

## Risks / Trade-offs

- Additional local subprocess per refresh → bounded by the shared deadline; no model request.
- Login is user-owned → ask the user to run `claude auth login --claudeai`; verify real quotas after they complete it.
- Authenticated CLI output might also differ → report separately and extend only against observed quota data.

## Validation outcome

The user confirmed the login had expired. After renewing it, the public authentication command reports an authenticated subscription and the real provider probe returns all four session/weekly quota metrics. No parser change was needed.

## Migration Plan

Build and test version 0.4.2, back up the installed executable, stop and replace it, and restart with its existing data. Build checksummed Linux artifacts and prepare a GitHub draft release against the existing commit, explicitly marking the pending source commit. Commit, push, tag, and public release await the user's requested review. Restore the saved executable if deployment fails.
