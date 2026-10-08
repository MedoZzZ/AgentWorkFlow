# Linux setup and verification

The same Markdown lifecycle, JSON settings, and PowerShell scripts work on Windows and Linux. Install PowerShell 7.2+ using [Microsoft's distribution instructions](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-linux), then install and authenticate [Antigravity CLI](https://antigravity.google/docs/cli/install/). Install the project's own runtimes separately.

Keep `antigravity.cliPath` empty for discovery through PATH or `~/.local/bin/agy`. If overriding it, use an absolute Linux path; `~` and environment variables inside JSON are not expanded. Reauthenticate with the Linux account; Windows credentials and command permissions are separate.

From the application directory in Bash:

```bash
pwsh --version
agy --help
pwsh -NoProfile -File ./workflow/scripts/Test-Configuration.ps1
pwsh -NoProfile -File ./workflow/scripts/Preflight.ps1 -ProjectRoot "$PWD"
pwsh -NoProfile -File ./workflow/scripts/Run-Antigravity.ps1 \
  -ProjectRoot "$PWD" -TaskFile "$PWD/workflow/tasks/TASK-001.md" \
  -RunId TASK-001-round-01
```

The last command defaults to read-only planning. Add `-Mode accept-edits` only for an implementation assignment after the required project review. Continuations use `-ConversationId` with the saved ID, as on Windows. No chmod or Bash-specific runner is needed.

Use Linux paths and Linux-compatible test/build commands in task files and CI.md. Quote paths containing spaces. Keep projects on native Linux storage when using WSL. Preserve task filename case: `project` and `PROJECT` can be different directories. Store dispatch evidence locally; the project file lock protects cooperating runner processes using the same filesystem. Shared/network filesystems need their own locking validation before concurrent use.

## Verification record

The framework's mock tests cover settings, model flags, error classifications, duplicate/concurrent dispatch protection, and cross-process locks. Linux additionally tests rejection of a task in a sibling directory differing only by case. GitHub Actions runs these checks on Windows and Ubuntu without Antigravity credentials.

Mock runner checks passed locally on Windows and Ubuntu WSL, with PowerShell 7.4.6 on Linux. Linux verified settings, failure classifications, duplicate IDs, cross-process file locking, and case-sensitive project containment. The hosted CI matrix has not run yet. A real Linux Antigravity dispatch and authentication remain untested because agy is absent from this Ubuntu environment. Application-specific checks require the actual project and runtimes. See PROGRESS.md.
