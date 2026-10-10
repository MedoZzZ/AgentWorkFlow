# Autonomous orchestration and Linux workspace plan

Status: approved for implementation by the user; orchestration and Linux support added. Testing explicitly deferred by the user. See ORCHESTRATION.md for the implemented interface and limitations.

## Assessment and gaps

The existing PowerShell runner owns dispatch, attempt IDs, timeout supervision, exclusive project locking, approval/dependency gates, snapshots, and executor output classification. Task-State owns task transitions. Record-Verification validates supplied review evidence and fingerprints; it does not perform code review or run tests. Recover-Task checks abandoned attempts against recorded process identities. The Node dashboard supplies read-only project/run APIs and SSE conversations.

Missing capabilities are workflow-level approval and checkpoints, whole-graph validation, deterministic scheduling, an end-to-end coordinator loop, approved verification command execution, focused repair orchestration, and a final workflow review. Current Linux CI includes the four PowerShell suites and dashboard tests, but fresh Linux execution of the expanded framework has not been verified. The current Ubuntu WSL environment lacks pwsh. Earlier Linux results documented in LINUX.md apply to the earlier framework, not all new functionality.

## Proposed architecture

Keep Markdown task headers authoritative for task lifecycle and existing run directories authoritative for executor evidence. Add a versioned approved-plan manifest with task IDs, task scope hashes, optional priorities, allowed verification commands (executable plus argument arrays and working directory), acceptance requirements, approval reference, and budgets. New tasks, changed scope, broader commands, or changed approval boundaries require escalation.

A deterministic scheduler validates duplicate/missing IDs and dependency cycles before dispatch, restricts work to approved scope, and selects an eligible task by priority then ordinal task ID. Dependency evidence must remain current. Completion requires every scoped task verified with current evidence plus a recorded final coordinator review. Blocked or stale tasks prevent completion.

A lightweight PowerShell controller persists workflow ID, approved-plan hash, current task/attempt/run, phase, elapsed budget, pending work, stop reason, and final review. Use a controller lease separate from the existing dispatch lock, with a consistent acquisition order; do not hold the dispatch lock while calling a script that acquires it. Atomic checkpoints and process identity records support restart reconciliation without resetting attempts.

Codex remains the reasoning coordinator during the active session: select work through the controller, dispatch Antigravity through the existing runner, inspect requirements and actual diffs, run approved checks, independently assess results, record verification, and request a focused repair when appropriate. Scripts enforce transitions and limits. A successful executor response never becomes automatic verification. Failed checks and review findings produce a bounded repair assignment preserving the task scope and conversation/attempt history.

After interruption, recovery checks live process identity, reconciles evidence, and resumes from a checkpoint only when safe. A persisted checkpoint is not a background reasoning engine. This implementation will operate autonomously within the active Codex session after approval; it will not claim continued reasoning after that session ends. A detached reasoning provider would require a separately specified and tested integration.

Extend existing read-only dashboard APIs/SSE with workflow phase, active/pending/completed/blocked tasks, verification and repair stage, consumed limits, stop reason, and final-review status. No execution controls or remote listener.

## Linux readiness

Retain PowerShell 7.2+ and dependency-free Node. Use native Linux agy discovery, platform-sensitive containment and ordinal path/hash handling, argument arrays, UTF-8 evidence, portable temporary paths, and explicit process/exit handling. Audit case-distinct files, symlinks, paths with spaces, missing runtimes, executable permissions, timeout termination, locking, and recovery on Linux. Do not use Windows agy or copy Windows credentials into Linux.

Update LINUX.md with installation prerequisites, Bash commands for all tests, preflight, approved workflow invocation/recovery, dashboard startup, localhost access, and explicit validation limitations. Keep Windows/Linux CI parity. Prefer a native Linux filesystem for WSL workspaces; do not promise network-filesystem locks without testing them.

## Planned files

- New workflow/scripts/Workflow-Plan.ps1: manifest validation, approved scope and limits.
- New workflow/scripts/Workflow-Scheduler.ps1: graph validation and deterministic next action.
- New workflow/scripts/Workflow-State.ps1: checkpoints, controller lease and stop reasons.
- New workflow/scripts/Invoke-Workflow.ps1: coordinator-facing orchestration interface, dispatch and resume integration.
- New workflow/scripts/Invoke-WorkflowChecks.ps1: approved command execution and captured results.
- New workflow/scripts/Test-Orchestration.ps1: multi-task controller integration fixtures.
- New workflow/WORKFLOW-PLAN-TEMPLATE.json and workflow/ORCHESTRATION.md: approval contract, coordinator protocol and recovery instructions.
- Targeted updates to Task-State.ps1, Read-Config.ps1, Evidence.ps1, Recover-Task.ps1 and Progress.ps1 where needed; preserve existing script parameters and configuration behavior.
- Extend workflow/dashboard/server.mjs, public assets and server tests using the existing API/SSE implementation.
- Update workflow/LINUX.md, README.md, workflow/VALIDATION.md and .github/workflows/framework-checks.yml.

Workflow checkpoints will live below workflow/runs so existing evidence exclusions avoid self-invalidating snapshots. Add configuration through an optional versioned orchestration section or separate plan manifest without breaking existing schema-1 settings.

## Implementation sequence

1. Approve this architecture and the active-session autonomy boundary.
2. Implement plan validation and scheduler; test graph errors, approval scope, priorities, stale dependencies and completion gates.
3. Implement checkpoints and controller; integrate existing runner and locks; test sequential dispatch, duplicate prevention and budget enforcement.
4. Implement approved checks and coordinator review/repair protocol; preserve independent verification and attempt history.
5. Implement recovery, final review, dashboard observability and Linux setup; run the integration matrix and document actual evidence.

Once approved, proceed through these stages without routine intermediate approval requests. Escalate only for a real scope/architecture change, required permissions, unsafe recovery, exhausted budgets, or final acceptance.

## Validation

Use local executor mocks and real child processes without model access: multiple approved tasks, ordered dependencies, successful completion, failed review then repair, exhausted repairs, task/workflow timeout, interrupted controller, still-live executor, restart without duplicate dispatch, missing approval, changed approved scope, stale verification, invalid/cyclic graph, unexpected edits, and final review withholding completion. Verify SSE reflects checkpoints and reconnects without invented progress.

Run existing PowerShell and Node suites plus new integration tests on Windows and Linux. Check case sensitivity, UTF-8/line endings, spaces, process supervision, explicit nonzero exits and cross-process locks. Report local results separately from configured but unobserved hosted CI. Linux prerequisites may need installation before local execution; do not report a pass from configuration alone.

A real Antigravity API smoke test remains pending explicit authorization to send its prompt and referenced workflow contents to Google's API after the earlier automatic approval rejection. Mock integration and portability work can proceed without that external dispatch.

## Risks and limits

Review quality depends on active Codex reasoning; scripted checks alone cannot establish semantic correctness. Workspace edits can stale previously verified dependencies, so revalidate before dispatch and completion. Process termination can leave partial edits; resume must reconcile rather than erase them. Cross-filesystem locking behavior needs separate validation. Approved commands must remain explicit and bounded. Preserve existing interfaces and user work; no deployment, destructive cleanup, credential migration, or wider access is implied by plan approval.
