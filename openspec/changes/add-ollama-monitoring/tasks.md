## 1. Domain and configuration

- [x] 1.1 Add `ollama` to the provider-kind enum and serialization while preserving existing provider settings.
- [x] 1.2 Extend the normalized metric vocabulary for instantaneous loaded-model counts and resource-memory byte values, including JSON round trips and aggregate-safety validation.
- [x] 1.3 Add Ollama provider validation for base URL, optional protected credential, loopback HTTP preference and enabled/disabled state.
- [x] 1.4 Add settings and cache tests covering an Ollama provider and regression tests for settings/cache without Ollama.

## 2. Ollama provider adapter

- [x] 2.1 Implement a read-only `GET /api/ps` request with the existing timeout, response-size cap, redirect policy and URL safety checks.
- [x] 2.2 Implement fail-closed parsing of the response for model count, model names, optional memory/VRAM bytes and optional future unload time.
- [x] 2.3 Add fixtures for an idle server, one loaded model, multiple loaded models, optional unload time and protected-server responses.
- [x] 2.4 Add provider tests for healthy idle/loaded snapshots, missing Authorization without a credential, Bearer usage with a credential, 401/403 errors and malformed schema rejection.
- [x] 2.5 Register Ollama in the provider factory and make connection testing use only a valid `/api/ps` response, treating an empty model list as healthy.

## 3. Configuration workflow

- [x] 3.1 Add Ollama to the provider-type selector, default a new entry to disabled and `http://localhost:11434`, and show only URL, credential, secure-storage, loopback and enablement controls.
- [x] 3.2 Add save, restore and validation tests for HTTPS URLs, loopback HTTP, optional protected credentials and enabled/disabled state.
- [x] 3.3 Verify connection-test feedback distinguishes a healthy idle Ollama instance from unreachable, unauthorized and malformed server responses without exposing credential material.

## 4. Presentation

- [x] 4.1 Format loaded-model counts and per-model memory/VRAM values in dashboard, tooltip and overlay presentation without percentage tracks or balance wording.
- [x] 4.2 Render model unload time with model-unload wording and preserve stale/error state alongside cached observations.
- [x] 4.3 Add presentation tests for fresh, stale, error, no-model and multi-model Ollama snapshots.

## 5. Verification and documentation

- [x] 5.1 Run unit/fixture tests and the affected Linux and Windows release builds.
- [x] 5.2 Document Ollama setup, coverage, explicitly unsupported token/cost data, remote HTTPS behavior and secure credential handling.
- [x] 5.3 Review requests, fixtures, settings diagnostics and cache output for plaintext credentials, inferred usage or generation calls.

## 6. Ollama Cloud account plan

- [x] 6.1 Send one bounded, read-only `POST /api/me` alongside the loaded-model request, reusing the existing timeout, response cap, redirect policy and URL safety checks.
- [x] 6.2 Parse only account name and plan, drop the e-mail and identifiers, and keep the snapshot healthy with no label when the request fails or the schema is unrecognized.
- [x] 6.3 Add fixtures and tests for a signed-in account, an unrecognized body and an error status, asserting the loaded-model metrics survive each case.
- [x] 6.4 Document that the account plan is observable but the monthly and consumed credits are not published by any Ollama API.

## 7. Ollama Cloud monthly credits

- [x] 7.1 Add a separate, secret-stored ollama.com credential that is sent only to `ollama.com` and never to the configured base URL.
- [x] 7.2 Query `GET /api/usage` when that credential exists and map the monthly fraction to percentage metrics plus per-model request counts.
- [x] 7.3 Present the reported fraction as used and remaining percentages only, producing no currency figure.
- [x] 7.4 Degrade to partial on any credit-lookup failure while preserving the loaded-model observation and the credential's secrecy.
- [x] 7.5 Add fixtures and tests for reported credits, an idle account, an absent credential, the absence of any currency metric and fail-closed schema rejection.
- [x] 7.6 Document the endpoint, its undocumented status, the credential separation and the absence of token and currency data.
