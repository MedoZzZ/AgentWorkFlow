# Approved workflow orchestration

Approve the project plan once, then the active Codex coordinator drives all scoped tasks through independent review and bounded repairs. User input is needed for changed scope/architecture, permissions, exhausted limits, unsafe recovery and final acceptance. Deployment is outside this controller's scope.

## Prepare approval

Create managed tasks using TASK-STATE.md, then generate a draft with current task scope hashes:

```powershell
./workflow/scripts/New-WorkflowPlan.ps1 -ProjectRoot . -WorkflowId project-01 `
  -TaskFiles workflow/tasks/TASK-001.md,workflow/tasks/TASK-002.md
```

Edit workflow/WORKFLOW-PLAN.json before execution. Record real user approval in approvalReference, select exact allowedFiles per task, approve check executables/argument arrays/working directories and acceptance criterion names, and set limits. Larger priority runs first; ties use ordinal Task ID. Dependencies must match task headers. Missing/cyclic dependencies, duplicate IDs, changed scope and invalid settings stop execution. Dependencies outside dispatch scope must already be verified with current evidence. The draft generator leaves approval and editable/check/acceptance scopes empty so a draft cannot execute.

Check workingDirectory is an empty string for the project root or a relative directory. Workspace paths use forward slashes without traversal or symbolic links. Commands launch directly with argument arrays; shell syntax is interpreted only if an explicitly approved shell is the executable. platform is all, windows or linux. A skipped required check prevents verification; prepare platform-specific plans where commands differ. Optional checks may be skipped/unavailable; a failed check always prevents verification.

## Run and coordinate

```powershell
./workflow/scripts/Invoke-Workflow.ps1 -ProjectRoot . -PlanFile workflow/WORKFLOW-PLAN.json
```

Drive advances until independent reasoning is required. The active Codex coordinator reads the checkpoint and actual artifacts, makes a review decision, and invokes the next action without routine human approvals. For integrations, -Coordinator accepts a trusted scriptblock receiving a request object; returning the appropriate evidenceFile or decisionFile lets the controller loop across tasks automatically. No default callback silently approves executor output. Callbacks must supply real independent reasoning and respect the deadline; arbitrary caller-provided callback execution is not forcibly supervised.

A task-review request includes the task, approved checks, captured results, snapshot, plan hash and state. Inspect actual diffs, existing user changes, test edits, acceptance criteria and unexpected edits. Check artifacts live under workflow/runs/RUN/checks; checks.json holds current results. Use VERIFICATION-TEMPLATE.json. Named checks/statuses/required flags must match captured execution; approved acceptance criteria must appear. Capture current fingerprint/scope hash, include every changed file and actual supporting evidence. Do not report skipped checks as passed.

```powershell
./workflow/scripts/Invoke-Workflow.ps1 -ProjectRoot . -PlanFile workflow/WORKFLOW-PLAN.json `
  -Action Review -EvidenceFile workflow/runs/RUN/review-input.json
```

A needs-fix verdict requires repairFindings with concrete defects, corrections and recheck instructions. The controller saves findings and continues the existing Antigravity conversation when available, preserving scope, attempt IDs and evidence. Record-Verification controls verified transitions. Executor SUCCESS never substitutes for independent verification.

Failures, interruptions or stale verified work require a repair-diagnosis decision. Supply JSON: schemaVersion 1, workflowId, planHash, taskId, latest runId, testedFingerprint, action repair, findings, scopeChanged false and permissionChanged false. Permission denials or edits outside approved boundaries require escalation. The controller detects unauthorized edits after execution; it does not provide a filesystem sandbox.

```powershell
./workflow/scripts/Invoke-Workflow.ps1 -ProjectRoot . -PlanFile workflow/WORKFLOW-PLAN.json `
  -Action Repair -DecisionFile workflow/runs/repair-decision.json
```

Attempt limits include existing attempts from previous workflows. maxRepairAttempts permits that many additional attempts after the first. Limits/history never silently reset. Workflow duration is wall-clock time from first start, including time between coordinator actions. Task/check timeouts cannot exceed remaining workflow budget.

## Recovery and final review

```powershell
./workflow/scripts/Invoke-Workflow.ps1 -ProjectRoot . -PlanFile workflow/WORKFLOW-PLAN.json -Action Resume
```

Resume checks recorded process identity before reconciling abandoned implementation or checks. Live children prevent recovery. Recover-Task records partial implementation; coordinator diagnosis is required before retry. Incomplete checks retain captured results and mark missing results unavailable. Review partial edits before repair. Resume preserves run directories, attempts, approvals and limits. A dependency-blocked checkpoint can resume after reconciliation; boundary violations require escalation rather than automatic retry.

Atomic checkpoints live under workflow/runs/_workflows/WORKFLOW-ID/state.json, excluded from source fingerprints. approved-plan.json preserves the approval input. The controller lease is separate from active.lock used by existing scripts. Only one unfinished workflow is admitted. Editing the approved plan invalidates it. Checkpoints support recovery; they do not provide autonomous reasoning after the Codex session ends.

After every scoped task is currently verified, supply final-review JSON: schemaVersion 1, workflowId, planHash, current testedFingerprint, verdict complete, scopeReviewed true, nonempty evidence, and taskRecords mapping every Task ID to its current verification.record. Technical completion remains separate from user acceptance.

```powershell
./workflow/scripts/Invoke-Workflow.ps1 -ProjectRoot . -PlanFile workflow/WORKFLOW-PLAN.json `
  -Action FinalReview -EvidenceFile workflow/runs/final-review-input.json
```

-Action Stop -Reason 'Explanation' records a stop. The read-only dashboard exposes checkpoints through /api/workflows and project SSE: phase, active task/run/attempt, current pending/completed work, blockers, repairs, limits, final review and stop reason. A checkpoint is the last recorded action, not proof a process remains running.

If the user approves a replacement scope, reconcile all implementation/check attempts first. Before changing task scopes, use -Action Supersede -DecisionFile with JSON containing schemaVersion 1, workflowId, planHash, the new user approvalReference and reason. This preserves the old workflow as superseded and permits a newly approved workflow. Superseding never clears task attempts or grants new execution permissions.

## Build status

These additions have not been executed or tested on Windows or Linux, at the user's request. New orchestration integration coverage and real Linux validation remain pending. Existing scripts and schema-1 configuration remain supported.

## Governance additions

New drafts enable governance.requireReviewerIdentity and use REVIEW-TEMPLATE.json (schema 2). Final reviews use FINAL-REVIEW-TEMPLATE.json. Schema-1 review evidence remains available for older plans. See GOVERNANCE.md for identity/revision attestation, the Recheck action, decision records, migration requirements, release evaluation and portfolio registration.
