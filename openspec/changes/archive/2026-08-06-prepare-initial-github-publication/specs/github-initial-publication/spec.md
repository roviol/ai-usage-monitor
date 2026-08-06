## ADDED Requirements

### Requirement: Publication preflight
The publication workflow SHALL inspect the exact candidate snapshot for generated artifacts, runtime data, oversized files, and likely credentials before creating the first commit or any remote repository.

#### Scenario: Generated files are excluded
- **WHEN** the candidate snapshot is assembled
- **THEN** dependency caches, build outputs, packaged distributions, runtime data, and user-specific IDE state are absent from the staged file set

#### Scenario: Suspicious content is found
- **WHEN** a likely credential, private key, credential-bearing URL, or unexpectedly large file is detected
- **THEN** publication stops until the item is reviewed and either removed, ignored, or explicitly confirmed safe

### Requirement: Explicit repository identity gate
The publication workflow MUST obtain the user's explicit repository-name and visibility selections before creating a GitHub repository.

#### Scenario: Candidate names are presented
- **WHEN** the preflight is complete
- **THEN** the workflow presents product-relevant repository names whose current availability has been checked for the authenticated GitHub owner

#### Scenario: No selection has been made
- **WHEN** a repository name or visibility remains undecided
- **THEN** no GitHub repository is created and no push is attempted

#### Scenario: Selected name is no longer available
- **WHEN** the chosen name fails the final availability check
- **THEN** creation stops and the workflow requests another name without altering local history

### Requirement: Deliberate initial Git history
The publication workflow SHALL create the first commit on a branch named `main` only after the staged files and available project verification have passed review.

#### Scenario: Candidate snapshot passes review
- **WHEN** ignore behavior, staged file names, staged content, and project verification are acceptable
- **THEN** the workflow creates one initial commit on `main` containing that reviewed snapshot

#### Scenario: Candidate snapshot fails review
- **WHEN** any staged-content or project verification check fails
- **THEN** no commit and no remote repository are created

### Requirement: GitHub creation and push
The publication workflow SHALL create a repository under the authenticated GitHub owner using the selected name and visibility, configure it as `origin`, and push local `main`.

#### Scenario: Remote publication succeeds
- **WHEN** the initial commit exists and the selected name remains available
- **THEN** the GitHub repository is created with the chosen visibility and local `main` is pushed as the tracked `origin/main`

#### Scenario: Push fails after remote creation
- **WHEN** GitHub creates the repository but the initial push fails
- **THEN** the workflow retains the local commit and remote repository, reports the failure state, and performs no destructive rollback

### Requirement: Post-publication verification
The publication workflow MUST verify that local and remote repository state agree before reporting success.

#### Scenario: Publication is complete
- **WHEN** the push finishes
- **THEN** the worktree is clean, `main` tracks `origin/main`, local and remote commit IDs match, and GitHub reports the selected repository name and visibility

#### Scenario: Verification detects a mismatch
- **WHEN** any local/remote state differs from the selected or committed state
- **THEN** the workflow reports the mismatch and does not claim publication is complete
