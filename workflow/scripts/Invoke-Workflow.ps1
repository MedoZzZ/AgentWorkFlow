#requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][string]$PlanFile,
    [ValidateSet('Drive','Resume','Review','Repair','Recheck','FinalReview','Stop','Supersede')][string]$Action='Drive',
    [string]$EvidenceFile,
    [string]$DecisionFile,
    [string]$Reason,
    # A trusted integration can provide reasoning decisions. No built-in fake reviewer.
    [scriptblock]$Coordinator,
    [string]$CliPath,
    [string]$ConfigPath
)
$ErrorActionPreference='Stop'
foreach ($file in @('Platform.ps1','Task-State.ps1','Evidence.ps1','Progress.ps1','Workflow-Plan.ps1','Workflow-Scheduler.ps1','Workflow-State.ps1')) { . (Join-Path $PSScriptRoot $file) }
$root=(Resolve-Path -LiteralPath $ProjectRoot).Path
$planPath=(Resolve-Path -LiteralPath $PlanFile).Path
$relativePlan=[IO.Path]::GetRelativePath($root,$planPath).Replace('\','/')
$null=Resolve-WorkflowLocalPath $root $relativePlan
$plan=Read-WorkflowPlan $root $planPath
$planHash=(Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash
$runs=Join-Path $root 'workflow/runs'
$null=Resolve-WorkflowLocalPath $root 'workflow/runs'
$null=Resolve-WorkflowLocalPath $root "workflow/runs/_workflows/$($plan.workflowId)"
New-Item -ItemType Directory -Path $runs -Force | Out-Null
# Controller lease is deliberately distinct from active.lock held by existing scripts.
$lease=[IO.File]::Open((Join-Path $runs 'controller.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::Write,[IO.FileShare]::None)
$directory=Join-Path $runs "_workflows/$($plan.workflowId)"
$checkpoint=Join-Path $directory 'state.json'
$state=$null
function Invoke-WorkflowLocked([scriptblock]$Operation) {
    $lock=[IO.File]::Open((Join-Path $runs 'active.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try { & $Operation } finally { $lock.Dispose() }
}
function Assert-WorkflowDecision($Decision, [string]$TaskId, [string]$RunId) {
    if ($Decision.schemaVersion -ne 1 -or $Decision.workflowId -cne $plan.workflowId -or $Decision.planHash -ne $planHash -or $Decision.taskId -cne $TaskId -or $Decision.runId -cne $RunId -or $Decision.testedFingerprint -ne (Get-WorkflowSnapshot $root).fingerprint) { throw 'Coordinator decision identity, approval or fingerprint is stale.' }
    if ($Decision.scopeChanged -isnot [bool] -or $Decision.scopeChanged -or $Decision.permissionChanged -isnot [bool] -or $Decision.permissionChanged) { throw 'Scope or permission change requires new approval.' }
}
function Submit-WorkflowReview([string]$Path) {
    if (-not $state.activeTask -or -not $state.activeRun) { throw 'No active task review.' }
    $index=Get-WorkflowTaskIndex $root $plan; $item=$index[$state.activeTask]
    $evidence=Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
    if ($evidence.taskId -cne $state.activeTask -or $evidence.runId -cne $state.activeRun) { throw 'Review must match active task and run.' }
    $checkResult=Get-Content -LiteralPath (Join-Path $runs "$($state.activeRun)/checks.json") -Raw | ConvertFrom-Json -AsHashtable
    if ($checkResult.testedFingerprint -ne $evidence.testedFingerprint -or $checkResult.unexpectedChanges.Count) { throw 'Check evidence stale or contains unexpected edits.' }
    foreach ($approved in $item.plan.checks) {
        $actual=@($checkResult.checks | Where-Object name -CEQ $approved.name)
        $claimed=@($evidence.checks | Where-Object name -CEQ $approved.name)
        if ($actual.Count -ne 1 -or $claimed.Count -ne 1 -or $claimed[0].status -cne $actual[0].status -or $claimed[0].required -ne $approved.required) { throw "Check review differs from captured execution: $($approved.name)" }
    }
    foreach ($criterion in $item.plan.acceptanceCriteria) {
        $claimed=@($evidence.acceptanceCriteria | Where-Object name -CEQ $criterion.name)
        if ($claimed.Count -ne 1 -or $claimed[0].required -ne $criterion.required) { throw "Missing approved acceptance criterion: $($criterion.name)" }
    }
    foreach ($change in $checkResult.changes) { if ($change.path -cnotin $evidence.scope) { throw 'Verification omits a file changed by independent checks.' } }
    if ($evidence.verdict -eq 'needs-fix' -and [string]::IsNullOrWhiteSpace($evidence.repairFindings)) { throw 'A repair verdict requires focused repairFindings.' }
    & (Join-Path $PSScriptRoot 'Record-Verification.ps1') -ProjectRoot $root -TaskFile $item.path -EvidenceFile $Path -RequireReviewerIdentity:([bool]$plan.governance.requireReviewerIdentity) | Out-Null
    if ($evidence.verdict -eq 'needs-fix') {
        $repair=Join-Path $directory "$($state.activeTask)-repair.txt"
        [IO.File]::WriteAllText($repair,$evidence.repairFindings,[Text.UTF8Encoding]::new($false))
        $state.repairs[$state.activeTask]=@{file=$repair; hash=(Get-FileHash -LiteralPath $repair -Algorithm SHA256).Hash; runId=$state.activeRun; fingerprint=$evidence.testedFingerprint}
    }
    if ($evidence.verdict -eq 'blocked') { Save-WorkflowCheckpoint $checkpoint $state stopped 'Independent verification blocked continuation.' }
    else { Save-WorkflowCheckpoint $checkpoint $state scheduling }
}
function Submit-WorkflowRepair([string]$Path) {
    $decision=Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
    $index=Get-WorkflowTaskIndex $root $plan
    if (-not $index.ContainsKey($decision.taskId) -or -not $index[$decision.taskId].approved) { throw 'Repair must reference an approved task.' }
    $item=$index[$decision.taskId]; $task=$item.data
    $lastRun=if ($task.attempts.Count) { $task.attempts[-1].runId } else { '' }
    Assert-WorkflowDecision $decision $task.taskId $lastRun
    if ($decision.action -cne 'repair' -or [string]::IsNullOrWhiteSpace($decision.findings) -or $task.status -notin @('failed','interrupted','verified','needs-fix')) { throw 'Repair requires an eligible task and focused diagnosis.' }
    if ($lastRun) {
        $metadata=Get-Content -LiteralPath (Join-Path $runs "$lastRun/metadata.json") -Raw | ConvertFrom-Json -AsHashtable
        Assert-WorkflowNoLiveProcess $metadata
        if ($metadata.status -in @('blocked-permissions','unexpected-task-state-change','unexpected-task-scope-change','unexpected-file-changes','unexpected-plan-changes')) { throw 'Boundary violation requires escalation, not automatic repair.' }
        $changePath=Join-Path $runs "$lastRun/changes.json"
        if (Test-Path -LiteralPath $changePath) { $changes=(Get-Content -LiteralPath $changePath -Raw | ConvertFrom-Json -AsHashtable).changes }
        else {
            $baseline=Get-Content -LiteralPath (Join-Path $runs "$lastRun/before.json") -Raw | ConvertFrom-Json -AsHashtable
            $changes=Compare-WorkflowSnapshot $baseline (Get-WorkflowSnapshot $root)
        }
        if (@($changes | Where-Object { $_.path -cnotin $item.plan.allowedFiles }).Count) { throw 'Current partial changes exceed approved repair scope.' }
    }
    if ($task.attempts.Count -ge (1+$plan.limits.maxRepairAttempts)) { throw 'Task attempt budget exhausted.' }
    Invoke-WorkflowLocked {
        if ($task.status -eq 'verified') { Set-WorkflowTaskTransition $item.path $task needs-fix 'Coordinator diagnosed stale verification.' }
        elseif ($task.status -in @('failed','interrupted')) { Set-WorkflowTaskTransition $item.path $task ready 'Coordinator reviewed partial changes and approved bounded repair.' }
    }
    $repair=Join-Path $directory "$($task.taskId)-repair.txt"
    [IO.File]::WriteAllText($repair,$decision.findings,[Text.UTF8Encoding]::new($false))
    $state.repairs[$task.taskId]=@{file=$repair; hash=(Get-FileHash -LiteralPath $repair -Algorithm SHA256).Hash; runId=$lastRun; fingerprint=$decision.testedFingerprint}
    Write-WorkflowJson (Join-Path $directory "decision-$([guid]::NewGuid().ToString('N')).json") $decision
    Save-WorkflowCheckpoint $checkpoint $state scheduling
}
function Submit-WorkflowRecheck([string]$Path) {
    $decision=Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
    $index=Get-WorkflowTaskIndex $root $plan
    if (-not $index.ContainsKey($decision.taskId) -or -not $index[$decision.taskId].approved) { throw 'Recheck must reference an approved task.' }
    $item=$index[$decision.taskId]; $task=$item.data
    if (-not $task.attempts.Count -or $task.status -notin @('verified','needs-fix') -or $decision.action -cne 'recheck' -or [string]::IsNullOrWhiteSpace($decision.findings)) { throw 'Recheck requires a prior completed attempt and independent diagnosis.' }
    Assert-WorkflowDecision $decision $task.taskId $task.attempts[-1].runId
    $metadata=Get-Content -LiteralPath (Join-Path $runs "$($task.attempts[-1].runId)/metadata.json") -Raw | ConvertFrom-Json -AsHashtable
    if ($metadata.status -ne 'SUCCESS') { throw 'Failed/partial executor work requires repair diagnosis.' }
    Invoke-WorkflowLocked {
        if ($task.status -eq 'verified') { Set-WorkflowTaskTransition $item.path $task needs-fix 'Review evidence invalidated; coordinator requested independent recheck.' }
        Set-WorkflowTaskTransition $item.path $task ready-for-verification $decision.findings $task.attempts[-1].runId $task.attempts[-1].attemptId
        $checkPath=Join-Path $runs "$($task.attempts[-1].runId)/checks.json"
        if (Test-Path -LiteralPath $checkPath) {
            $old=Get-Content -LiteralPath $checkPath -Raw | ConvertFrom-Json -AsHashtable
            $old['recheckRequested']=$true
            Write-WorkflowJson $checkPath $old
        }
    }
    $state.repairs.Remove($task.taskId)
    Write-WorkflowJson (Join-Path $directory "recheck-$([guid]::NewGuid().ToString('N')).json") $decision
    Save-WorkflowCheckpoint $checkpoint $state scheduling
}
function Restore-WorkflowCheckEvidence($Item) {
    $task=$Item.data
    if ($task.status -ne 'ready-for-verification' -or -not $task.attempts.Count) { return }
    $run=Join-Path $runs $task.attempts[-1].runId
    $path=Join-Path $run 'check-process.json'
    if (-not (Test-Path -LiteralPath $path)) { return }
    $record=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
    if ($record.status -notin @('running','abandoned')) { return }
    Assert-WorkflowNoLiveProcess $record
    Invoke-WorkflowLocked {
        $snapshot=Get-WorkflowSnapshot $root
        $beforePath=Resolve-WorkflowLocalPath $root "$($record.directory)/before.json"
        $baseline=Get-Content -LiteralPath $beforePath -Raw | ConvertFrom-Json -AsHashtable
        $checkChanges=Compare-WorkflowSnapshot $baseline $snapshot
        $changePath=Join-Path $run 'changes.json'
        $original=if (Test-Path -LiteralPath $changePath) { (Get-Content -LiteralPath $changePath -Raw | ConvertFrom-Json -AsHashtable).changes } else { @() }
        $combined=[Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
        foreach ($change in (@($original)+@($checkChanges))) { $combined[$change.path]=$change }
        $changes=@($combined.Values)
        Write-WorkflowJson $changePath @{changes=$changes}
        $results=@($record.checks)
        foreach ($check in $Item.plan.checks) {
            if ($check.name -cnotin @($results | ForEach-Object name)) { $results+=@{name=$check.name; required=$check.required; status='unavailable'; evidence='Check interrupted before a captured result; coordinator must review partial changes.'} }
        }
        $result=@{schemaVersion=1; taskId=$task.taskId; runId=$task.attempts[-1].runId; checks=$results; testedFingerprint=$snapshot.fingerprint; taskScopeHash=(Get-WorkflowTaskScopeHash $Item.path); changes=$changes; unexpectedChanges=@($checkChanges | Where-Object { $_.path -cnotin $Item.plan.allowedFiles }); recordedUtc=[DateTime]::UtcNow.ToString('o'); recovered=$true}
        Write-WorkflowJson (Join-Path $run 'checks.json') $result
        $record.status='interrupted'; $record['recoveredUtc']=$result.recordedUtc
        Write-WorkflowJson $path $record
    }
}
function Submit-WorkflowFinalReview([string]$Path) {
    $index=Get-WorkflowTaskIndex $root $plan
    $next=Get-WorkflowNextAction $root $plan $index
    if ($next.kind -ne 'final-review') { throw 'Final review requires all approved tasks currently verified.' }
    $review=Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
    if ($review.schemaVersion -ne 1 -or $review.workflowId -cne $plan.workflowId -or $review.planHash -ne $planHash -or $review.testedFingerprint -ne (Get-WorkflowSnapshot $root).fingerprint -or $review.verdict -cne 'complete' -or $review.scopeReviewed -isnot [bool] -or -not $review.scopeReviewed -or [string]::IsNullOrWhiteSpace($review.evidence)) { throw 'Final review must attest to current complete approved scope.' }
    foreach ($entry in $plan.tasks) {
        if ($review.taskRecords[$entry.taskId] -cne $index[$entry.taskId].data.verification.record) { throw 'Final review must reference every current task verification record.' }
        if ($plan.governance.requireReviewerIdentity) {
            $task=$index[$entry.taskId].data
            $metadata=Get-Content -LiteralPath (Join-Path $runs "$($task.attempts[-1].runId)/metadata.json") -Raw | ConvertFrom-Json -AsHashtable
            Assert-WorkflowReviewer $review $metadata (Get-WorkflowSnapshot $root)
        }
    }
    $state.finalReview=$review
    Write-WorkflowJson (Join-Path $directory 'final-review.json') $review
    Save-WorkflowCheckpoint $checkpoint $state complete
}
try {
    $index=Get-WorkflowTaskIndex $root $plan
    if (Test-Path -LiteralPath $checkpoint) {
        $state=Get-Content -LiteralPath $checkpoint -Raw | ConvertFrom-Json -AsHashtable
        if ($state.schemaVersion -ne 1 -or $state.planHash -ne $planHash -or $state.workflowId -cne $plan.workflowId) { throw 'Approved plan changed; create a newly approved workflow instead of resetting history.' }
    } else {
        # Never introduce another workflow while an unfinished one exists.
        $workflowRoot=Join-Path $runs '_workflows'
        if (Test-Path -LiteralPath $workflowRoot) {
            foreach ($file in Get-ChildItem -LiteralPath $workflowRoot -Filter state.json -Recurse -File) {
                $previous=Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -AsHashtable
                if ($previous.phase -notin @('complete','superseded')) { throw "Unfinished workflow $($previous.workflowId) must be reconciled before starting another." }
            }
        }
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        Copy-Item -LiteralPath $planPath -Destination (Join-Path $directory 'approved-plan.json')
        $state=@{schemaVersion=1; workflowId=$plan.workflowId; planHash=$planHash; planFile=$relativePlan; approvalReference=$plan.approvalReference; coordinatorMode='active-session'; startedUtc=[DateTime]::UtcNow.ToString('o'); updatedUtc=''; phase='scheduling'; activeTask=$null; activeRun=$null; activeAttempt=$null; completed=@(); pending=@(); blocked=@(); history=@(); repairs=@{}; limits=$plan.limits; stopReason=''; finalReview=$null}
        Invoke-WorkflowLocked {
            foreach ($entry in $plan.tasks) {
                $item=$index[$entry.taskId]
                $item.data.approval=$plan.approvalReference
                Write-WorkflowTask $item.path $item.data
            }
        }
        Save-WorkflowCheckpoint $checkpoint $state scheduling
    }
    $state['controllerProcessId']=$PID
    $state['controllerStartedUtc']=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')
    if ($state.phase -eq 'complete') {
        $current=Get-WorkflowNextAction $root $plan $index
        if ($current.kind -ne 'final-review' -or $state.finalReview.testedFingerprint -ne (Get-WorkflowSnapshot $root).fingerprint) {
            $state.finalReview=$null
            Save-WorkflowCheckpoint $checkpoint $state scheduling 'Previous completion evidence became stale.'
        }
    }
    if ($Action -eq 'Supersede') {
        $decision=Get-Content -LiteralPath $DecisionFile -Raw | ConvertFrom-Json -AsHashtable
        if ($decision.schemaVersion -ne 1 -or $decision.workflowId -cne $plan.workflowId -or $decision.planHash -ne $planHash -or [string]::IsNullOrWhiteSpace($decision.approvalReference) -or [string]::IsNullOrWhiteSpace($decision.reason)) { throw 'Superseding requires a recorded new user approval and reason.' }
        foreach ($entry in $plan.tasks) {
            $item=$index[$entry.taskId]
            if ($item.data.status -eq 'in-progress') { throw 'Reconcile implementation attempts before superseding.' }
            if ($item.data.attempts.Count) {
                $processPath=Join-Path $runs "$($item.data.attempts[-1].runId)/check-process.json"
                if (Test-Path -LiteralPath $processPath) {
                    $record=Get-Content -LiteralPath $processPath -Raw | ConvertFrom-Json -AsHashtable
                    if ($record.status -in @('running','abandoned')) { throw 'Reconcile check execution before superseding.' }
                }
            }
        }
        $state['supersededApproval']=$decision
        Save-WorkflowCheckpoint $checkpoint $state superseded $decision.reason
    } elseif ($Action -eq 'Stop') {
        if ([string]::IsNullOrWhiteSpace($Reason)) { throw 'Stop requires a reason.' }
        Save-WorkflowCheckpoint $checkpoint $state stopped $Reason
    } else {
        if ($state.phase -eq 'superseded') { throw 'Superseded workflows cannot resume; history remains preserved.' }
        if ($Action -in @('Review','Repair','Recheck','FinalReview') -and (Get-WorkflowRemainingSeconds $state $plan) -le 0) { throw 'Workflow duration exhausted.' }
        if ($Action -eq 'Resume') {
            foreach ($entry in $plan.tasks) {
                $item=$index[$entry.taskId]
                Restore-WorkflowCheckEvidence $item
                if ($item.data.status -eq 'in-progress') {
                    $last=$item.data.attempts[-1]
                    $metadata=Get-Content -LiteralPath (Join-Path $runs "$($last.runId)/metadata.json") -Raw | ConvertFrom-Json -AsHashtable
                    Assert-WorkflowNoLiveProcess $metadata
                    & (Join-Path $PSScriptRoot 'Recover-Task.ps1') -ProjectRoot $root -TaskFile $item.path -Reason 'Controller resumed after interruption; partial changes require coordinator diagnosis.' | Out-Null
                }
            }
            if ($state.phase -notin @('complete','stopped') -or $state.stopReason -eq 'No eligible task: blocked tasks, live attempts, or stale/unapproved dependencies.') { Save-WorkflowCheckpoint $checkpoint $state scheduling }
        }
        if ($Action -eq 'Review') { Submit-WorkflowReview $EvidenceFile }
        if ($Action -eq 'Repair') { Submit-WorkflowRepair $DecisionFile }
        if ($Action -eq 'Recheck') { Submit-WorkflowRecheck $DecisionFile }
        if ($Action -eq 'FinalReview') { Submit-WorkflowFinalReview $EvidenceFile }
        while ($state.phase -notin @('complete','stopped')) {
            if ((Get-FileHash -LiteralPath $planPath -Algorithm SHA256).Hash -ne $planHash) { throw 'Approved plan changed during execution.' }
            $remaining=Get-WorkflowRemainingSeconds $state $plan
            if ($remaining -le 0) { Save-WorkflowCheckpoint $checkpoint $state stopped 'Workflow duration exhausted.'; break }
            $index=Get-WorkflowTaskIndex $root $plan
            $next=Get-WorkflowNextAction $root $plan $index
            $state.completed=@($next.completed); $state.pending=@($next.pending); $state.blocked=@($next.blocked)
            if ($next.kind -eq 'blocked') { Save-WorkflowCheckpoint $checkpoint $state stopped 'No eligible task: blocked tasks, live attempts, or stale/unapproved dependencies.'; break }
            if ($next.kind -eq 'final-review') {
                $state.activeTask=$null; $state.activeRun=$null; $state.activeAttempt=$null
                Save-WorkflowCheckpoint $checkpoint $state awaiting-final-review
                if (-not $Coordinator) { break }
                $decision=& $Coordinator @{kind='final-review'; state=$state; plan=$plan; planHash=$planHash; snapshot=(Get-WorkflowSnapshot $root); tasks=$index}
                if (-not $decision.evidenceFile) { Save-WorkflowCheckpoint $checkpoint $state stopped 'Coordinator did not supply final review.'; break }
                Submit-WorkflowFinalReview $decision.evidenceFile
                continue
            }
            $item=$next.task; $task=$item.data
            $state.activeTask=$task.taskId; $state.activeRun=if ($task.attempts.Count) { $task.attempts[-1].runId } else { $null }
            $state.activeAttempt=if ($task.attempts.Count) { $task.attempts[-1].attemptId } else { $null }
            if ($next.kind -eq 'repair') {
                if ($task.status -ne 'verified' -and $task.attempts.Count -ge (1+$plan.limits.maxRepairAttempts)) { Save-WorkflowCheckpoint $checkpoint $state stopped 'Task attempt budget exhausted.'; break }
                $repair=$state.repairs[$task.taskId]
                $current=(Get-WorkflowSnapshot $root).fingerprint
                if (-not $repair -or $repair.runId -cne $state.activeRun -or $repair.fingerprint -ne $current -or $task.status -ne 'needs-fix') {
                    # Failure/interrupt retries always need independent diagnosis; executor status is insufficient.
                    Save-WorkflowCheckpoint $checkpoint $state awaiting-repair-diagnosis
                    if (-not $Coordinator) { break }
                    $decision=& $Coordinator @{kind='repair-diagnosis'; state=$state; task=$item; planHash=$planHash; snapshot=(Get-WorkflowSnapshot $root)}
                    if (-not $decision.decisionFile) { Save-WorkflowCheckpoint $checkpoint $state stopped 'Coordinator did not supply a safe repair diagnosis.'; break }
                    $request=Get-Content -LiteralPath $decision.decisionFile -Raw | ConvertFrom-Json -AsHashtable
                    if ($request.action -eq 'recheck') { Submit-WorkflowRecheck $decision.decisionFile }
                    else { Submit-WorkflowRepair $decision.decisionFile }
                    continue
                }
                $next.kind='dispatch'
            }
            if ($next.kind -eq 'task-review') {
                Save-WorkflowCheckpoint $checkpoint $state verifying
                $processPath=Join-Path $runs "$($state.activeRun)/check-process.json"
                if (Test-Path -LiteralPath $processPath) {
                    $processRecord=Get-Content -LiteralPath $processPath -Raw | ConvertFrom-Json -AsHashtable
                    if ($processRecord.status -in @('running','abandoned')) { throw 'Unreconciled check execution; use Resume after inspecting its process.' }
                }
                $checkPath=Join-Path $runs "$($state.activeRun)/checks.json"
                $captured=if (Test-Path -LiteralPath $checkPath) { Get-Content -LiteralPath $checkPath -Raw | ConvertFrom-Json -AsHashtable } else { $null }
                if (-not $captured -or $captured.recheckRequested -or $captured.testedFingerprint -ne (Get-WorkflowSnapshot $root).fingerprint) {
                    $deadline=([DateTime]$state.startedUtc).ToUniversalTime().AddSeconds($plan.limits.workflowTimeoutSeconds).ToString('o')
                    & (Join-Path $PSScriptRoot 'Invoke-WorkflowChecks.ps1') -ProjectRoot $root -PlanFile $planPath -TaskId $task.taskId -RunId $state.activeRun -DeadlineUtc $deadline | Out-Null
                    $captured=Get-Content -LiteralPath $checkPath -Raw | ConvertFrom-Json -AsHashtable
                }
                if ($captured.unexpectedChanges.Count) { Save-WorkflowCheckpoint $checkpoint $state stopped 'Independent checks changed files outside approved scope.'; break }
                Save-WorkflowCheckpoint $checkpoint $state awaiting-task-review
                if (-not $Coordinator) { break }
                $decision=& $Coordinator @{kind='task-review'; state=$state; task=$item; checks=$captured; planHash=$planHash; snapshot=(Get-WorkflowSnapshot $root)}
                if (-not $decision.evidenceFile) { Save-WorkflowCheckpoint $checkpoint $state stopped 'Coordinator did not supply independent review evidence.'; break }
                Submit-WorkflowReview $decision.evidenceFile
                continue
            }
            if ($task.attempts.Count -ge (1+$plan.limits.maxRepairAttempts)) { Save-WorkflowCheckpoint $checkpoint $state stopped 'Task attempt budget exhausted.'; break }
            if ($remaining -lt 10) { Save-WorkflowCheckpoint $checkpoint $state stopped 'Insufficient workflow duration for dispatch.'; break }
            if ($task.status -eq 'draft') {
                & (Join-Path $PSScriptRoot 'Set-TaskStatus.ps1') -ProjectRoot $root -TaskFile $item.path -Status ready -Reason "Approved workflow: $($plan.approvalReference)" | Out-Null
            }
            $runId="$($plan.workflowId)-$($task.taskId)-$([guid]::NewGuid().ToString('N'))"
            $state.activeRun=$runId; $state.activeAttempt=$null
            $dispatch=@{ProjectRoot=$root; TaskFile=$item.path; RunId=$runId; Mode='accept-edits'; TimeoutSeconds=[int][Math]::Min($remaining,$plan.limits.taskTimeoutSeconds); MaxRepairAttempts=$plan.limits.maxRepairAttempts; Stream=$true; AllowedFiles=$item.plan.allowedFiles; WorkflowId=$plan.workflowId}
            $dispatch.OnAttemptStarted={
                param($StartedAttempt, $StartedRun)
                $state.activeAttempt=$StartedAttempt; $state.activeRun=$StartedRun
                Save-WorkflowCheckpoint $checkpoint $state $state.phase
            }
            if ($CliPath) { $dispatch.CliPath=$CliPath }; if ($ConfigPath) { $dispatch.ConfigPath=$ConfigPath }
            if ($state.repairs[$task.taskId]) {
                $repair=$state.repairs[$task.taskId]
                if ($repair.fingerprint -ne (Get-WorkflowSnapshot $root).fingerprint) { throw 'Repair diagnosis is stale.' }
                $dispatch.RepairFile=$repair.file
                if ((Get-FileHash -LiteralPath $repair.file -Algorithm SHA256).Hash -ne $repair.hash) { throw 'Recorded repair instructions changed.' }
                if ($repair.runId) {
                    $prior=Get-Content -LiteralPath (Join-Path $runs "$($repair.runId)/metadata.json") -Raw | ConvertFrom-Json -AsHashtable
                    if ($prior.conversationId) { $dispatch.ConversationId=$prior.conversationId }
                }
            }
            Save-WorkflowCheckpoint $checkpoint $state $(if ($dispatch.RepairFile) { 'repairing' } else { 'dispatching' })
            try { & (Join-Path $PSScriptRoot 'Run-Antigravity.ps1') @dispatch | Out-Null }
            catch {
                $metaPath=Join-Path $runs "$runId/metadata.json"
                $meta=if (Test-Path -LiteralPath $metaPath) { Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json -AsHashtable } else { $null }
                $state.activeAttempt=$meta.attemptId
                if ($meta -and (Test-Path -LiteralPath (Join-Path $runs "$runId/before.json"))) {
                    $baseline=Get-Content -LiteralPath (Join-Path $runs "$runId/before.json") -Raw | ConvertFrom-Json -AsHashtable
                    $changes=Compare-WorkflowSnapshot $baseline (Get-WorkflowSnapshot $root)
                    if (@($changes | Where-Object { $_.path -cnotin $item.plan.allowedFiles }).Count) {
                        $meta.status='unexpected-file-changes'; $meta.outcome='unexpected-file-changes'
                        Write-WorkflowJson $metaPath $meta
                    }
                }
                if (-not $meta -or $meta.status -in @('blocked-permissions','unexpected-task-state-change','unexpected-task-scope-change','unexpected-file-changes','unexpected-plan-changes')) { Save-WorkflowCheckpoint $checkpoint $state stopped $_.Exception.Message; break }
                Save-WorkflowCheckpoint $checkpoint $state awaiting-repair-diagnosis $_.Exception.Message
            }
            $state.repairs.Remove($task.taskId)
            Save-WorkflowCheckpoint $checkpoint $state scheduling
        }
    }
    try { Invoke-WorkflowLocked { Sync-WorkflowProgress $root } }
    catch { $state['progressError']=$_.Exception.Message; Write-WorkflowJson $checkpoint $state }
    $state | ConvertTo-Json -Depth 30
} catch {
    if ($state -and $state.phase -notin @('complete','superseded')) { Save-WorkflowCheckpoint $checkpoint $state stopped $_.Exception.Message }
    throw
} finally { $lease.Dispose() }
$global:LASTEXITCODE=0
