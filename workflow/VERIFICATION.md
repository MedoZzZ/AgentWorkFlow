# Independent verification and recovery

Codex coordinates requirements, approved plans, task selection, dispatch, independent checks, repair feedback, and final user review. Antigravity remains the default coding executor. Stitch provides reviewed design references following STITCH-UI-UX.md. Actual tool access must be established in the current chat.

## Run evidence

Runner parameters and CLI modes remain compatible. Metadata retains status and adds outcome: planned, ready-for-verification, or a failure classification. Native executor processes have a runner-enforced timeout as well as the CLI print timeout. Child-process termination is requested on timeout; inspect actual files before retrying. In-process .ps1 mock adapters retain existing test behavior and are not timeout-supervised.

Each run saves before.json, after.json, changes.json, task-at-dispatch.md, and task-at-return.md alongside existing logs and metadata. Snapshots record SHA256 hashes and Git HEAD when available, including uncommitted and untracked files. Changes identify added, modified, and deleted paths. Task copies preserve assigned scope and returned reports. Detected plan-mode mutations, managed header changes, and edits to assigned instructions/acceptance scope before the Executor result section are rejected.

Snapshots exclude directories named .git, node_modules, and .pilot, plus workflow/runs, workflow/tasks, and workflow/PROGRESS.md. The selected task is separately checked in plan mode and its acceptance scope is hashed during verification. Other task files and excluded directories require manual review. Included symlinks/reparse points stop snapshotting. Large included build outputs increase snapshot cost. Snapshots detect changes; they do not isolate or roll back execution.

## Record a coordinator verdict

1. Inspect changes.json and the actual diff, including test modifications and unexpected changes. Compare against every acceptance criterion and approved design where applicable.
2. Run independent checks and preserve actual output. Record passed, failed, skipped, and unavailable outcomes separately. Inspect UI behavior for UI tasks. Executor test reports remain executor evidence.
3. Copy VERIFICATION-TEMPLATE.json into workflow/runs/<RunId>/review-input.json. Fill identities, checks, acceptance criteria, review flags, verdict, and scope. Scope lists every changed file plus supporting source/test/config files; include deleted paths. Excluded files cannot be selected.
4. Capture tested state after checks using the helpers below. If files changed during checks, rerun affected checks before capturing it.

```powershell
. ./workflow/scripts/Task-State.ps1
. ./workflow/scripts/Evidence.ps1
$testedState = Get-WorkflowSnapshot -ProjectRoot $PWD.Path
$testedState.fingerprint
Get-WorkflowTaskScopeHash -TaskFile './workflow/tasks/TASK-001.md'
./workflow/scripts/Record-Verification.ps1 -ProjectRoot $PWD.Path -TaskFile './workflow/tasks/TASK-001.md' -EvidenceFile './workflow/runs/TASK-001-01/review-input.json'
```

Run under pwsh with appropriate Linux paths on Linux. Keep review input under workflow/runs so it does not alter the source fingerprint.

Record-Verification rejects stale file/scope fingerprints, wrong attempts, omitted changed files, missing reviews, invalid checks, and verified verdicts with failed or incomplete required checks. It appends a uniquely named record under the run's verification directory and updates the task. Optional skipped checks remain explicit. The framework validates record shape; it cannot establish whether a human performed a check or listed every criterion. Records are preserved by convention, not protected against filesystem writers.

Before a dependent task becomes ready or dispatches, dependencies require current scoped hashes and acceptance scope. Unrelated file edits do not invalidate a dependency. Include supporting files in scope accordingly. Generated progress preserves task state; it does not continuously monitor for stale evidence. User acceptance and release authorization remain separate records.

## Repairs and recovery

On needs-fix, append observed failure, expected behavior, focused repair instructions, and evidence to Repair history. Dispatch with a new Run ID; preserve earlier results. Rerun failed checks and relevant regressions. Do not weaken acceptance criteria or remove failing tests to get a pass.

The runner allows one initial implementation plus three repairs by default, counting failed/interrupted attempts too. -MaxRepairAttempts accepts 0–20 and is recorded in metadata. At the limit, diagnose and replan with the user. No automatic repair loop is launched. Managed implementation continuation requires a conversation ID previously recorded for that Task ID.

For an abandoned in-progress attempt, inspect metadata, task copies, logs, processes, and actual files, then run:

```powershell
./workflow/scripts/Recover-Task.ps1 -ProjectRoot $PWD.Path -TaskFile './workflow/tasks/TASK-001.md' -Reason 'Executor stopped; reviewed partial edits'
./workflow/scripts/Set-TaskStatus.ps1 -ProjectRoot $PWD.Path -TaskFile './workflow/tasks/TASK-001.md' -Status ready -Reason 'Partial changes reconciled; safe to retry approved scope'
```

Recovery holds the project lock, refuses a recorded native executor still running, compares current files with the saved baseline, preserves a report, and marks interrupted. The runner also blocks new dispatches while any persisted run is still marked running, even after its original coordinator exits. It never resets files, deletes locks, reuses a Run ID, or retries. Detached descendants/external tools still require inspection. Legacy interrupted runs require manual metadata reconciliation after process/file inspection. Failed/blocked tasks require explicit inspection and transition before retrying. Interrupted verification remains pending; inspect any saved record and repeat checks before a new verdict.

## Components and validation

Antigravity-Adapter.ps1 owns invocation/output capture and normalization. Another executor can implement Invoke-WorkflowExecutor and Read-WorkflowExecutorResult without replacing lifecycle/evidence code; public provider selection is not implemented. Task-State.ps1 owns headers/transitions; Evidence.ps1 owns snapshots/atomic JSON writes; Progress.ps1 replaces only its marked summary section. Public commands hold the project lock. Normal tool permissions remain in force; shared filesystem access is not an executor/coordinator security boundary.

Run Test-Configuration.ps1, Test-TaskState.ps1, and Test-Evidence.ps1. CI includes Windows and Ubuntu. Distinguish local mocks, native process tests, live Antigravity runs, hosted CI, and project UI verification.
