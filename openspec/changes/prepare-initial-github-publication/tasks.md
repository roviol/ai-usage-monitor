## 1. Publication Preflight

- [x] 1.1 Inventory visible and hidden project files, generated directories, runtime data, and the largest candidate files
- [x] 1.2 Scan candidate text files for concrete credential, private-key, token, and credential-bearing URL signatures and review every match
- [x] 1.3 Update `.gitignore` for any generated or user-local paths found by the audit, while retaining safe project workflow metadata
- [x] 1.4 Confirm the intended first-commit contents contain no build, dependency-cache, package, runtime-data, or IDE-user artifacts

## 2. Repository Decisions

- [x] 2.1 Check product-relevant repository-name candidates under the authenticated GitHub owner and present the available options
- [x] 2.2 Record the user's explicit repository-name and public/private visibility selections
- [x] 2.3 Recheck the selected name immediately before remote creation and stop if it is unavailable

## 3. Local Git Initialization

- [x] 3.1 Initialize the local repository with `main` as the initial branch and verify repository-local identity is usable
- [x] 3.2 Stage the intended snapshot and review ignored files, staged file names, staged sizes, and the complete staged diff
- [x] 3.3 Run the existing automated test suite or the highest-confidence available build/test preset and resolve any publication-blocking failure
- [x] 3.4 Create one initial commit with a concise message and verify that the worktree is clean

## 4. GitHub Publication

- [x] 4.1 Create the GitHub repository under the authenticated owner with the selected name and visibility, configure `origin`, and push `main`
- [ ] 4.2 Verify `main` tracks `origin/main`, local and remote commit IDs match, and GitHub reports the selected name and visibility
- [ ] 4.3 Report the repository URL, initial commit ID, verification results, and any intentionally excluded paths
