# Managed task lifecycle

New tasks use the leading `workflow-task` JSON comment in TASK-TEMPLATE.md. This header is the authoritative task state; the visible Status line is synchronized by the scripts. Keep the header at the start of the file. Assign a unique taskId, record the actual user instruction or approval reference in approval, and list dependency Task IDs. An approval string records a human decision; it does not authenticate that decision.

Task Markdown remains the only state store. attempts records implementation Attempt IDs and their Run IDs. history preserves timestamped transitions and reasons. Run metadata links Task ID, Run ID, and Attempt ID. Planning runs do not create implementation attempts or change task status.

## Coordinator commands

```powershell
./workflow/scripts/Set-TaskStatus.ps1 -ProjectRoot 'C:/Projects/MyApp' -TaskFile 'C:/Projects/MyApp/workflow/tasks/TASK-001.md' -Status ready -Reason 'User approved scope in PROJECT-SPEC.md'
./workflow/scripts/Run-Antigravity.ps1 -ProjectRoot 'C:/Projects/MyApp' -TaskFile 'C:/Projects/MyApp/workflow/tasks/TASK-001.md' -RunId TASK-001-01 -Mode accept-edits
./workflow/scripts/Record-Verification.ps1 -ProjectRoot 'C:/Projects/MyApp' -TaskFile 'C:/Projects/MyApp/workflow/tasks/TASK-001.md' -EvidenceFile 'C:/Projects/MyApp/workflow/runs/TASK-001-01/review-input.json'
```

These scripts also run under pwsh on Linux with Linux paths. Both use the existing exclusive project lock. Writes replace the task file atomically. The runner owns implementation transitions and header updates; Antigravity fills the Executor result section.

## Allowed transitions

| From | Allowed destinations |
| --- | --- |
| draft | ready, blocked |
| ready | in-progress, blocked |
| in-progress | ready-for-verification, failed, interrupted, blocked |
| ready-for-verification | verified, needs-fix, blocked |
| needs-fix | in-progress, blocked |
| failed, interrupted | ready, blocked |
| blocked | draft, ready, needs-fix |
| verified | needs-fix |

Only the runner starts in-progress. Becoming ready and starting implementation require a nonempty approval reference, unique managed Task IDs, and verified dependencies. Missing dependencies prevent dispatch. Failed checks return the task to needs-fix; further execution appends a new attempt. Permission-denied results become blocked; other caught dispatch failures become failed. A hard process kill can leave in-progress: inspect logs and partial changes, record interrupted, then record the reason it is safe to become ready again.

## Compatibility and current boundaries

Existing headerless tasks still execute with metadata taskManagement=`legacy-unmanaged`. They do not receive lifecycle, approval, or dependency enforcement. Migrate implementation tasks by adding the template header and recording their actual state; do not invent prior approvals or verification. Malformed headers are rejected rather than treated as legacy.

Set-TaskStatus is a coordinator tool, not an authorization boundary against an executor with filesystem access. Verified requires Record-Verification with structured independent evidence. Dependency dispatch rejects stale scoped hashes and changed acceptance scope. The runner enforces repair limits and native-process timeouts; Recover-Task records interrupted reconciliation without retrying. See [VERIFICATION.md](VERIFICATION.md) for formats, exclusions, commands, and boundaries.

Tests: Test-TaskState.ps1 covers approval, dependency and duplicate-ID rejection, transitions, planning isolation, attempt identity, repair history, permission failure, malformed headers, and lock exclusion. GitHub Actions includes the suite on Windows and Ubuntu; hosted execution must be observed separately.
