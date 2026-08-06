## Why

The project is not yet under Git version control, so its source, documentation, tests, and build metadata cannot be reviewed or published reproducibly on GitHub. Before the first commit, the directory needs a publication-readiness check and the repository name and visibility must be explicitly selected.

## What Changes

- Audit the project tree for generated artifacts, local-only files, oversized files, and credentials before staging anything.
- Define the intended first-commit contents and strengthen ignore rules where the audit finds gaps.
- Present repository-name options derived from the product identity and verify the selected name for the authenticated GitHub owner.
- Initialize Git with `main`, create a deliberate initial commit, create the GitHub repository with the chosen visibility, and push `main` only after the user selects the name and authorizes implementation.
- Verify the local/remote state after publication without changing application behavior.

## Capabilities

### New Capabilities

- `github-initial-publication`: Defines the safeguards, explicit decisions, and verification required to publish this directory as a new GitHub repository for the first time.

### Modified Capabilities

None.

## Impact

The change affects repository metadata (`.gitignore` and `.git`), the first Git history entry, and a new repository under the authenticated GitHub account. Application source and runtime behavior are not expected to change. GitHub repository creation and push are deferred until the user chooses a name and visibility.
