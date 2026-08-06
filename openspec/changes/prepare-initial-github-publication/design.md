## Context

The directory contains a C++20/CMake desktop application, tests, documentation, GitHub Actions workflows, OpenSpec history, and project-local Claude/Codex workflow definitions. It also contains generated dependency, build, distribution, and runtime-data directories that are already covered by `.gitignore`. The directory has no `.git` metadata. GitHub CLI is authenticated as `roviol` over HTTPS.

Publication is externally visible and difficult to undo completely once consumers clone or fork it. The process therefore needs a hard decision gate before remote creation and a preflight based on the exact files that Git will stage.

## Goals / Non-Goals

**Goals:**

- Produce a reviewable first-commit file set with generated and local runtime artifacts excluded.
- Detect likely credentials, private keys, credential-bearing URLs, and oversized files before committing.
- Obtain an explicit repository name and visibility selection before creating anything on GitHub.
- Create a single initial commit on `main`, publish it with `gh`, and verify local/remote agreement.
- Preserve useful project automation and planning metadata when it is safe to publish.

**Non-Goals:**

- Changing application behavior or finishing unrelated in-progress OpenSpec changes.
- Publishing release binaries, creating a GitHub release, or configuring branch protection.
- Rewriting files merely to make the first commit appear smaller.
- Deleting a newly created remote automatically if a later verification step fails.

## Decisions

### Treat the staged snapshot as the source of truth

Initialize Git locally only after the user authorizes implementation, stage with `git add`, and audit `git diff --cached` plus the staged file list before committing. This is more reliable than auditing a manually assembled directory listing because it tests the exact snapshot that will be published. The alternative of committing first and reviewing afterward risks placing sensitive data in history even if it is removed in a later commit.

### Keep project workflow metadata, exclude generated state

The first commit will include `.github`, `.claude`, `.codex`, source, tests, docs, packaging, and OpenSpec artifacts unless the staged audit identifies private content. It will exclude `.deps`, `build`, `dist`, `data`, `.vs`, and per-user IDE files through `.gitignore`. The alternative of ignoring all dot-directories would discard reproducible project workflows and CI configuration.

### Require explicit remote identity choices

Repository creation is blocked until the user selects a verified available name and chooses `public` or `private`. Candidate names will be derived from the product name and checked under the authenticated owner immediately before creation. The alternative of inferring a name from the folder (`ia-usage`) could publish under an unclear product identity.

### Use one GitHub CLI creation flow

After the local `main` commit exists, use `gh repo create <owner>/<name> --source . --remote origin --push` with the selected visibility. This keeps remote creation, remote configuration, and the first push in one inspectable operation. Manual browser creation is unnecessary because `gh` is already authenticated.

### Verify publication without destructive rollback

Verify a clean worktree, `main` tracking `origin/main`, equal local and remote commit IDs, and the repository metadata returned by GitHub. If remote creation succeeds but push or verification fails, retain the local commit and remote for diagnosis; do not delete or recreate either automatically.

## Risks / Trade-offs

- [A broad secret scan can report legitimate words such as “password” in source code] → Review matched file names and staged diffs; use signatures for concrete token/key formats in addition to generic terms.
- [Ignore rules can omit a file needed to reproduce the build] → Review ignored files and keep only dependency caches, build outputs, packages, runtime data, and user-specific IDE state excluded.
- [A repository name can become unavailable between checking and creation] → Recheck immediately before `gh repo create` and return to the selection gate if unavailable.
- [Public visibility can expose project history immediately] → Require visibility explicitly and default the recommendation to private when the user has not chosen.
- [Remote creation may succeed while push fails] → Leave both sides intact, report their exact state, and retry only the failed non-destructive step.

## Migration Plan

1. Re-run the directory, ignore-rule, file-size, and credential preflight.
2. Present checked candidate names and collect the selected name and visibility.
3. Initialize Git on `main`, stage the intended snapshot, and review the staged file set and diff.
4. Run the existing test suite or the highest-confidence available verification before committing.
5. Create the initial commit with a concise conventional message.
6. Recheck remote-name availability, create the GitHub repository, set `origin`, and push `main`.
7. Verify tracking, commit equality, worktree cleanliness, visibility, and repository URL.

If any check before remote creation fails, unstage or amend local files without publishing. If a post-creation check fails, keep the state for diagnosis and avoid automatic deletion.

## Open Questions

- Which repository name does the user select from the available candidates?
- Should the GitHub repository be public or private?
