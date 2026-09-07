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

- [ ] 5.1 Run unit/fixture tests and the affected Linux and Windows release builds.
- [x] 5.2 Document Ollama setup, coverage, explicitly unsupported token/cost data, remote HTTPS behavior and secure credential handling.
- [x] 5.3 Review requests, fixtures, settings diagnostics and cache output for plaintext credentials, inferred usage or generation calls.
