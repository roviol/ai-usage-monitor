## 1. Authentication-aware capture

- [x] 1.1 Add public authentication probing, actionable typed errors, legacy fallback, and a shared deadline.
- [x] 1.2 Add regression tests for login, API billing, legacy clients, malformed output, timeout, cancellation, privacy, and valid quota capture.

## 2. Verification and installation

- [x] 2.1 Update troubleshooting/privacy documentation and version 0.4.2 release metadata.
- [x] 2.2 Build and run unit/fixture tests and validate OpenSpec.
- [x] 2.3 Install and restart the application; verify the real logged-out diagnostic and stale data preservation.
- [x] 2.4 After user login, verify real subscription quota capture and correct any observed incompatibility.

## 3. Release preparation

- [x] 3.1 Build checksummed Linux release artifacts and run release gates.
- [x] 3.2 Prepare release notes and a GitHub draft release; keep commit, push, tag, and public release pending user approval after authenticated validation.
