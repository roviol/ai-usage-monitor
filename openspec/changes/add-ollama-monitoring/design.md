## Context

The provider architecture already normalizes process/API-backed providers through `IUsageProvider`, uses injectable HTTP and secret-store ports, and persists provider configuration and last-good snapshots. Ollama exposes a public local HTTP API whose `/api/ps` endpoint reports loaded models without generating text. The existing generic OpenAI-compatible adapter cannot describe instantaneous loaded-model observations honestly because its contract assumes configurable usage, quota, balance or token mappings.

## Goals / Non-Goals

**Goals:**

- Reuse the existing provider factory, scheduler, caching, secret storage and safe URL policy.
- Add a purpose-built Ollama adapter that maps only validated `/api/ps` fields.
- Make Ollama configuration simple: base URL, optional credential, enable/disable and loopback HTTP.
- Preserve old settings and cache behavior while introducing Ollama-only metric kinds.
- Make Ollama coverage obvious in dashboard, tooltip and overlay presentation.

**Non-Goals:**

- Query Ollama models or invoke generation, completion, embedding or other inference routes.
- Infer token totals, quotas, costs or historical usage.
- Support Ollama's private implementation details or read its local storage.
- Manage Ollama models, processes, configuration or unload scheduling.

## Decisions

### 1. New provider kind and normalizer

Add an `ollama` provider kind and a dedicated `OllamaProvider`. It will issue a bounded `GET /api/ps`, validate the response as an object containing an optional `models` array, and accept only validated entries. The connection test will use the same read-only request so an empty model list remains a successful, healthy result.

Alternative considered: use the generic OpenAI-compatible provider with `/api/ps` and JSON Pointer mappings. This was rejected because it cannot naturally express model counts, per-model resource observations or model unload time and risks conflating Ollama status with billing-style usage.

### 2. Instantaneous resource metrics

Extend the normalized metric vocabulary with `loaded-models` as a count and `resource-memory` in bytes, using an `current-observation` scope and provider-reported provenance. Each snapshot gets one aggregate loaded-model count and one per-model memory/VRAM metric when `size_vram` is valid. Model names live in labels; a future `expires_at` is attached to the per-model metric as unload time and displayed with model-unload wording, not quota-reset wording.

Alternative considered: represent model count through the existing requests metric. This was rejected as semantically wrong and potentially misleading in aggregation and tooltips.

### 3. Conservative transport and credentials

The adapter will use the existing 10-second timeout, 1 MiB response cap and disabled-redirect policy. The default base URL is `http://localhost:11434` with loopback HTTP enabled for newly added Ollama providers. Remote HTTP remains rejected unless the user's explicit loopback exception covers a loopback address. An optional credential is protected with the existing secret store and sent only as `Authorization: Bearer`; diagnostics continue to redact credential material.

Alternative considered: add Ollama-specific host parsing or environment-variable discovery. This is unnecessary for the first capability because the base URL already expresses local and remote configurations.

### 4. Fail-closed parser and partial coverage

A successful `/api/ps` response with no loaded models is healthy and produces a zero loaded-model metric. Invalid JSON, non-array models, invalid entries, negative byte counts or invalid future unload timestamps throw a schema error rather than producing invented metrics. Token, quota, spend and balance are explicitly unsupported; no generic fallback route is attempted.

### 5. UI and presentation reuse

Preferences will add an "Ollama" type and show only base URL, optional credential, secure storage, loopback HTTP and enable controls. Dashboard, tooltip and overlay presentation models will handle the new instantaneous kinds without treating them as percentages or balances. Ollama rows will state that they are loaded-model status, not AI usage.

## Risks / Trade-offs

- [Ollama schema or fields evolve] → Validate only recognized fields, fail closed on schema change, and add fixtures before extending behavior.
- [Optional Bearer authentication is not available on every Ollama deployment] → Leave the credential blank by default and report authentication failures without redaction leaks.
- [Instantaneous loaded-model data can change between refresh intervals] → Preserve the observed timestamp, label it as current observation and never extrapolate.
- [New metric kinds require UI changes] → Add focused presentation tests so unknown/unsupported kinds remain hidden rather than becoming fake percentage bars.
- [Users may expect token/cost analytics] → Document that Ollama does not expose such quota data through `/api/ps`.

## Migration Plan

1. Extend the provider and metric enums with backward-compatible JSON identifiers, then add parsing/factory tests.
2. Add the Ollama adapter and fixtures for idle, single-model, multi-model, protected, error and malformed-schema cases.
3. Add the settings form and validation path, including secure credential handling and loopback defaults.
4. Update presentation, tooltip and overlay tests, then run Linux and Windows builds/tests.
5. Document Ollama coverage and removal/reversal behavior. Rollback only requires removing the new provider from settings; existing providers and cached data remain unchanged.
