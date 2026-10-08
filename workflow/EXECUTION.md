# Running the framework

Use PowerShell 7.2+ (`pwsh`) on Windows or Linux. From Bash run `pwsh -NoProfile -File ./workflow/scripts/Preflight.ps1 -ProjectRoot "$PWD"`; use the same form for Run-Antigravity.ps1 and Test-Configuration.ps1. See LINUX.md for setup and validation. Scripts share platform-aware CLI discovery, use portable paths, and preserve Linux path case sensitivity. Preflight records the OS and PowerShell version. Linux CLI authentication and scoped command permissions must be established on that machine.

Edit config.json for shared project defaults; see CONFIGURATION.md. Explicit runner arguments override settings. Default model is gemini-3.8-flash-high, mode is plan, and timeout is 600 seconds. Each run records its effective settings and a config snapshot.

## Preflight

Run scripts/Preflight.ps1 with -ProjectRoot set to the actual project directory. Inspect the reported Git baseline, existing changes, CLI availability, runtimes, and manifests. It discovers setup; it does not install packages or execute application checks. Fill CI.md with actual commands and run baseline checks before edits.

## Dispatch

Run scripts/Run-Antigravity.ps1 with -ProjectRoot, an absolute -TaskFile path inside that project, and a unique -RunId such as TASK-001-round-01. Default mode is read-only plan. Use -Mode accept-edits for an implementation assignment after the required project review. The runner preserves normal CLI permissions; it does not bypass approval requirements.

Each run saves preflight.json, prompt.txt, stdout.json, stderr.log, and metadata.json under workflow/runs/<RunId>. A permanent lock prevents duplicate use of the same ID. Review evidence before creating a new ID after a timeout or interruption: execution might have continued. Use the captured -ConversationId for a continuation only when it belongs to the intended task.

SUCCESS means the CLI returned successfully, not that acceptance criteria passed. The runner classifies reported denied actions as blocked-permissions and blank successful responses as empty-response. Inspect stderr, inspect actual changes, and independently verify. Update the task and PROGRESS.md after dispatch and verification. Caught startup/execution errors are recorded as failed; a hard process kill can still leave a running record, so reconcile actual state before resuming.

An OS-held active.lock prevents different run IDs from running concurrently in the same project and releases when the process exits. Permanent per-run locks still prevent reusing run IDs. The active.lock filename may remain on disk after completion; only an open exclusive file handle indicates an active dispatch.

## Git and context

Capture the baseline before editing. Preserve existing user work. Use small, reviewed commits as checkpoints when Git is available and the project permits it; avoid automatic reset or rollback. One executor at a time initially. Load only relevant specs and task context. Add a short project instruction file pointing to this workflow without overwriting existing instructions.

## Scope and evidence

Map requirement IDs to use cases, screen IDs, task IDs, and concrete evidence in the task files. Include important negative cases. For bugs, use the short path: reproduce -> diagnose -> repair -> verify, with affected design/architecture noted. Use the full planning path for new features.

After each milestone, record recurring failures and one actionable process improvement in PROGRESS.md. Keep deployment and recovery details in PROJECT-SPEC.md and ARCHITECTURE.md rather than creating duplicate records.

## Copying

Copy templates and scripts to new projects. Exclude workflow/runs, workflow/tasks/CONNECTION-SMOKE.md, CONNECTION-TEST.md, and prior project tasks/evidence. Initialize project progress and requirements afresh. Run artifacts can contain sensitive output; inspect/redact them before sharing or committing.

## Verification performed on the starter

Preflight ran against the starter directory and correctly reported the available CLI, no Git repository, and no application manifests. A live read-only dispatch returned RUNNER_OK and the exact README heading. A repeated run ID was rejected before CLI invocation. Evidence is in runs/runner-smoke-01/. Implementation edits, command permissions, timeout recovery, and conversation continuation have not been exercised yet; verify those when relevant to the first project.
