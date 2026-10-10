# Linux workspaces

Use native PowerShell 7.2+, Node 18.18+ (CI uses Node 22), and Antigravity CLI on Linux. Install application runtimes separately. Authenticate with the Linux account; do not invoke Windows agy.exe or transfer Windows credentials as a substitute for native setup.

Keep antigravity.cliPath empty for PATH or ~/.local/bin/agy discovery. Overrides must be absolute Linux paths; JSON does not expand tilde or environment variables. The runner checks executable permission before native dispatch. Use distribution-appropriate runtime vendor installation instructions.

From the project root in Bash:

```bash
pwsh --version
node --version
agy --help
bash ./workflow/scripts/workflow.sh preflight
```

Generate a draft using PowerShell array syntax:

```bash
pwsh -NoProfile -Command '& ./workflow/scripts/New-WorkflowPlan.ps1 -ProjectRoot . -WorkflowId project-01 -TaskFiles @("workflow/tasks/TASK-001.md","workflow/tasks/TASK-002.md")'
```

Fill the draft and record one plan approval as described in ORCHESTRATION.md. The active Codex coordinator drives and reviews all scoped work:

```bash
bash ./workflow/scripts/workflow.sh drive workflow/WORKFLOW-PLAN.json
# Inspect processes and evidence after interruption, then reconcile:
bash ./workflow/scripts/workflow.sh resume workflow/WORKFLOW-PLAN.json
# In a separate terminal:
bash ./workflow/scripts/workflow.sh dashboard -Port 4317
```

Open http://127.0.0.1:4317 locally. The server binds to 127.0.0.1 and requires the same local origin. For remote Linux, use an authenticated SSH local port forward, for example `ssh -L 4317:127.0.0.1:4317 USER@HOST`, then open the local address. Coordination remains on the host. WSL localhost forwarding depends on WSL configuration.

Direct PowerShell and Node invocations work too:

```bash
pwsh -NoProfile -File ./workflow/scripts/Invoke-Workflow.ps1 \
  -ProjectRoot "$PWD" -PlanFile "$PWD/workflow/WORKFLOW-PLAN.json"
pwsh -NoProfile -File ./workflow/scripts/Invoke-Workflow.ps1 \
  -ProjectRoot "$PWD" -PlanFile "$PWD/workflow/WORKFLOW-PLAN.json" \
  -Action Review -EvidenceFile "$PWD/workflow/runs/RUN/review-input.json"
node ./workflow/dashboard/server.mjs --project-root "$PWD" --port 4317
```

Standalone tasks retain Run-Antigravity.ps1 with plan or approved accept-edits mode and -Stream. The Bash wrapper forwards arguments to the same PowerShell engine; invoke with bash so its executable bit is optional.

Use forward-slash relative manifest paths, quote paths with spaces, preserve filename case, and approve native commands/argument arrays for the selected platform. UTF-8 evidence and OS-held locks are portable. Approved paths reject symbolic links. Prefer native Linux storage for WSL; cross-host/network filesystem locks require separate validation.

## Validation status

The new orchestration additions have not been run or tested on either platform, as requested. Current Ubuntu WSL lacks pwsh. Earlier Ubuntu PowerShell 7.4.6 results apply to older runner checks and do not validate these additions. Real Linux Antigravity dispatch/authentication remains unverified.

When validation is requested, existing suites run without model access:

```bash
pwsh -NoProfile -File ./workflow/scripts/Test-Configuration.ps1
pwsh -NoProfile -File ./workflow/scripts/Test-TaskState.ps1
pwsh -NoProfile -File ./workflow/scripts/Test-Evidence.ps1
pwsh -NoProfile -File ./workflow/scripts/Test-Streaming.ps1
node --test ./workflow/dashboard/test/server.test.mjs
```

The configured Windows/Ubuntu CI matrix includes these suites and PowerShell parsing; new orchestration integration coverage and observed hosted results remain pending. No live model dispatch is needed for mock validation.

## Governance on Linux

The governance scripts use the same PowerShell implementation on Linux. For example:

```bash
pwsh -NoProfile -File ./workflow/scripts/Register-Project.ps1 \
  -ProjectRoot "$PWD" -Id billing -Name 'Billing app' -Path '/home/user/projects/billing'
pwsh -NoProfile -File ./workflow/scripts/Record-Decision.ps1 \
  -ProjectRoot "$PWD" -InputFile "$PWD/workflow/runs/decision-input.json"
pwsh -NoProfile -File ./workflow/scripts/Check-Release.ps1 \
  -ProjectRoot "$PWD" -PlanFile "$PWD/workflow/RELEASE-PLAN.json" \
  -EvidenceFile "$PWD/workflow/runs/release-evidence.json"
```

Registry paths are local to the machine; re-register them after moving operating systems. The dashboard uses Git for revision freshness when a committed baseline exists; fingerprint checks still apply to projects without HEAD. No new runtime, migration or release operation was executed during this build.
