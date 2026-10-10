#requires -Version 7.2
# Evaluate recorded evidence only. Never merge, migrate or deploy.
param([Parameter(Mandatory)][string]$ProjectRoot, [Parameter(Mandatory)][string]$PlanFile, [Parameter(Mandatory)][string]$EvidenceFile)
$ErrorActionPreference='Stop'
foreach ($file in @('Platform.ps1','Task-State.ps1','Evidence.ps1','Workflow-Plan.ps1','Workflow-Scheduler.ps1')) { . (Join-Path $PSScriptRoot $file) }
$root=(Resolve-Path -LiteralPath $ProjectRoot).Path
$plan=Get-Content -LiteralPath $PlanFile -Raw | ConvertFrom-Json -AsHashtable
$evidence=Get-Content -LiteralPath $EvidenceFile -Raw | ConvertFrom-Json -AsHashtable
$planHash=(Get-FileHash -LiteralPath $PlanFile -Algorithm SHA256).Hash
if ($plan.schemaVersion -ne 1 -or $plan.releaseId -notmatch '^[A-Za-z0-9_-]+$' -or [string]::IsNullOrWhiteSpace($plan.target) -or $plan.requiredChecks -isnot [array] -or -not $plan.requiredChecks.Count -or $plan.workflowIds -isnot [array] -or -not $plan.workflowIds.Count) { throw 'Invalid release plan.' }
$runs=Resolve-WorkflowLocalPath $root 'workflow/runs'
New-Item -ItemType Directory -Path $runs -Force | Out-Null
$lock=[IO.File]::Open((Join-Path $runs 'active.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::Write,[IO.FileShare]::None)
try {
    $snapshot=Get-WorkflowSnapshot $root; $blockers=@()
    foreach ($name in $plan.requiredChecks) {
        if ([string]::IsNullOrWhiteSpace($name)) { throw 'Release check names cannot be empty.' }
        $checks=@($evidence.checks | Where-Object name -CEQ $name)
        if ($checks.Count -ne 1 -or $checks[0].status -cne 'passed' -or [string]::IsNullOrWhiteSpace($checks[0].evidence)) { $blockers+="Release check lacks passing evidence: $name" }
    }
    if ($evidence.schemaVersion -ne 1 -or $evidence.releaseId -cne $plan.releaseId -or $evidence.planHash -ne $planHash -or $evidence.testedFingerprint -ne $snapshot.fingerprint -or -not $evidence.ContainsKey('reviewedRevision') -or $evidence.reviewedRevision -cne $snapshot.revision) { $blockers+='Release evidence does not match exact plan, revision and files.' }
    if ($evidence.approval.releaseId -cne $plan.releaseId -or $evidence.approval.target -cne $plan.target -or $evidence.approval.fingerprint -ne $snapshot.fingerprint -or [string]::IsNullOrWhiteSpace($evidence.approval.reference) -or [string]::IsNullOrWhiteSpace($evidence.approval.approvedBy)) { $blockers+='Explicit human approval for this release target and fingerprint is missing.' }
    if ([string]::IsNullOrWhiteSpace($evidence.reviewer.id) -or [string]::IsNullOrWhiteSpace($evidence.reviewer.contextId) -or $evidence.reviewer.id -eq 'antigravity') { $blockers+='Independent release reviewer identity/context is missing.' }
    foreach ($id in $plan.workflowIds) {
        if ($id -notmatch '^[A-Za-z0-9_-]+$') { throw 'Invalid release Workflow ID.' }
        try {
            $base=Resolve-WorkflowLocalPath $root "workflow/runs/_workflows/$id"
            $state=Get-Content -LiteralPath (Join-Path $base 'state.json') -Raw | ConvertFrom-Json -AsHashtable
            $approved=Read-WorkflowPlan $root (Join-Path $base 'approved-plan.json')
            $index=Get-WorkflowTaskIndex $root $approved
            if ($state.phase -ne 'complete' -or $state.planHash -ne (Get-FileHash -LiteralPath (Join-Path $base 'approved-plan.json') -Algorithm SHA256).Hash -or $state.finalReview.testedFingerprint -ne $snapshot.fingerprint) { $blockers+="Workflow final review incomplete or stale: $id" }
            foreach ($task in $approved.tasks) {
                if (-not (Test-WorkflowVerificationCurrent $root $index[$task.taskId].path $index[$task.taskId].data)) { $blockers+="Task review stale: $($task.taskId)" }
                if (-not $index[$task.taskId].data.verification.revisionBound -or [string]::IsNullOrWhiteSpace($index[$task.taskId].data.verification.reviewer.id)) { $blockers+="Task lacks an identified revision-bound reviewer: $($task.taskId)" }
                $data=$index[$task.taskId].data
                if ($data.attempts.Count) {
                    $metadata=Get-Content -LiteralPath (Join-Path $runs "$($data.attempts[-1].runId)/metadata.json") -Raw | ConvertFrom-Json -AsHashtable
                    try { Assert-WorkflowReviewer $evidence $metadata $snapshot }
                    catch { $blockers+="Release review separation/attestation failed: $($_.Exception.Message)" }
                }
            }
        } catch { $blockers+="Workflow $id cannot satisfy release governance: $($_.Exception.Message)" }
    }
    $directory=Resolve-WorkflowLocalPath $root "workflow/runs/_releases/$($plan.releaseId)"
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $report=@{schemaVersion=1; releaseId=$plan.releaseId; target=$plan.target; planHash=$planHash; testedFingerprint=$snapshot.fingerprint; reviewedRevision=$snapshot.revision; status=$(if ($blockers.Count) { 'blocked' } else { 'ready-for-authorized-release' }); blockers=$blockers; evidence=$evidence; recordedUtc=[DateTime]::UtcNow.ToString('o'); actionExecuted=$false}
    Write-WorkflowJson (Join-Path $directory "$([guid]::NewGuid().ToString('N')).json") $report
    Write-WorkflowJson (Join-Path $directory 'latest.json') $report
    $report | ConvertTo-Json -Depth 30
    if ($blockers.Count) { throw 'Release gate blocked. Inspect the persisted report.' }
} finally { $lock.Dispose() }
$global:LASTEXITCODE=0
