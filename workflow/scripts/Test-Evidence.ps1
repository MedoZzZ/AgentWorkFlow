#requires -Version 7.2
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Task-State.ps1')
. (Join-Path $PSScriptRoot 'Evidence.ps1')
. (Join-Path $PSScriptRoot 'Platform.ps1')
. (Join-Path $PSScriptRoot 'Antigravity-Adapter.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('agentworkflow-evidence-' + [guid]::NewGuid().ToString('N'))
function Assert-Rejected {
    param([scriptblock]$Action, [string]$Pattern)
    try { & $Action | Out-Null } catch { if ($_.Exception.Message -notlike $Pattern) { throw }; return }
    throw "Expected rejection: $Pattern"
}
try {
    New-Item -ItemType Directory -Path (Join-Path $fixture 'workflow/tasks') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../config.json') -Destination (Join-Path $fixture 'workflow/config.json')
    $task = Join-Path $fixture 'workflow/tasks/TASK-001.md'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../TASK-TEMPLATE.md') -Destination $task
    $data = Read-WorkflowTask $task
    $data.taskId='TASK-001'; $data.status='ready'; $data.approval='User approved test scope'
    Write-WorkflowTask $task $data
    'original' | Set-Content -LiteralPath (Join-Path $fixture 'app.txt')
    $mock = Join-Path $fixture 'mock.ps1'
    '''updated'' | Set-Content -LiteralPath app.txt; $global:LASTEXITCODE=0; ''{"status":"SUCCESS","response":"done","conversation_id":"same-task"}''' | Set-Content -LiteralPath $mock
    $runner = Join-Path $PSScriptRoot 'Run-Antigravity.ps1'
    $base = @{ProjectRoot=$fixture; TaskFile=$task; CliPath=$mock}
    & $runner @base -RunId first -Mode accept-edits | Out-Null
    $run = Join-Path $fixture 'workflow/runs/first'
    $changes = Get-Content -LiteralPath (Join-Path $run 'changes.json') -Raw | ConvertFrom-Json
    if ($changes.changes.Count -ne 1 -or $changes.changes[0].path -ne 'app.txt') { throw 'Actual changes not captured.' }
    $snapshot = Get-WorkflowSnapshot $fixture
    $check = @{name='AC-1'; status='passed'; required=$true; evidence='Independent read of app.txt: updated'}
    $evidence = @{schemaVersion=1; taskId='TASK-001'; runId='first'; verdict='verified'; diffReviewed=$true; testChangesReviewed=$true; unexpectedChangesReviewed=$true; checks=@($check); acceptanceCriteria=@($check); testedFingerprint=$snapshot.fingerprint; taskScopeHash=(Get-WorkflowTaskScopeHash $task); scope=@('app.txt')}
    # Evidence input belongs under runs so recording it does not alter tested code state.
    $reviewInputPath = Join-Path $run 'review-input.json'
    $recorder = Join-Path $PSScriptRoot 'Record-Verification.ps1'
    $evidence.checks[0].status = 'unavailable'
    Write-WorkflowJson $reviewInputPath $evidence
    Assert-Rejected { & $recorder -ProjectRoot $fixture -TaskFile $task -EvidenceFile $reviewInputPath } '*incomplete required checks*'
    $evidence.checks[0].status = 'passed'
    $evidence.testedFingerprint='stale'
    Write-WorkflowJson $reviewInputPath $evidence
    Assert-Rejected { & $recorder -ProjectRoot $fixture -TaskFile $task -EvidenceFile $reviewInputPath } '*evidence is stale*'
    $evidence.testedFingerprint=$snapshot.fingerprint
    $evidence.scope=@('mock.ps1')
    Write-WorkflowJson $reviewInputPath $evidence
    Assert-Rejected { & $recorder -ProjectRoot $fixture -TaskFile $task -EvidenceFile $reviewInputPath } '*missing from verification scope*'
    $evidence.scope=@('app.txt')
    Write-WorkflowJson $reviewInputPath $evidence
    & $recorder -ProjectRoot $fixture -TaskFile $task -EvidenceFile $reviewInputPath | Out-Null
    if ((Read-WorkflowTask $task).status -ne 'verified') { throw 'Independent verification not persisted.' }
    $nextTask = Join-Path $fixture 'workflow/tasks/TASK-002.md'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../TASK-TEMPLATE.md') -Destination $nextTask
    $next = Read-WorkflowTask $nextTask
    $next.taskId='TASK-002'; $next.approval='Approved'; $next.dependencies=@('TASK-001')
    Write-WorkflowTask $nextTask $next
    Assert-WorkflowTaskReady $fixture $nextTask $next
    'changed after verification' | Set-Content -LiteralPath (Join-Path $fixture 'app.txt')
    Assert-Rejected { Assert-WorkflowTaskReady $fixture $nextTask $next } '*verification is stale*'
    $setter = Join-Path $PSScriptRoot 'Set-TaskStatus.ps1'
    & $setter -ProjectRoot $fixture -TaskFile $task -Status needs-fix -Reason 'Changed code requires recheck' | Out-Null
    Assert-Rejected { & $runner @base -RunId limited -Mode accept-edits -MaxRepairAttempts 0 } '*Repair attempt limit*'
    Assert-Rejected { & $runner @base -RunId wrong-conversation -Mode accept-edits -ConversationId wrong } '*Conversation ID*'
    # Simulate an abandoned attempt with a baseline and persisted running metadata.
    $data = Read-WorkflowTask $task
    $data.attempts += @{attemptId='abandoned'; runId='abandoned'}
    Set-WorkflowTaskTransition $task $data in-progress 'Simulated process termination' abandoned abandoned
    $abandoned = Join-Path $fixture 'workflow/runs/abandoned'
    New-Item -ItemType Directory -Path $abandoned | Out-Null
    Write-WorkflowJson (Join-Path $abandoned 'before.json') (Get-WorkflowSnapshot $fixture)
    Write-WorkflowJson (Join-Path $abandoned 'metadata.json') @{status='running'; runId='abandoned'}
    'partial changes' | Set-Content -LiteralPath (Join-Path $fixture 'app.txt')
    $recover = Join-Path $PSScriptRoot 'Recover-Task.ps1'
    Write-WorkflowJson (Join-Path $abandoned 'metadata.json') @{status='running'; runId='abandoned'; executorProcessId=$PID; executorStartedUtc=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')}
    Assert-Rejected { & $recover -ProjectRoot $fixture -TaskFile $task -Reason 'Must reject live process' } '*Executor is still running*'
    Write-WorkflowJson (Join-Path $abandoned 'metadata.json') @{status='running'; runId='abandoned'}
    Assert-Rejected { & $runner @base -RunId overlapping -Mode plan } '*unreconciled run*'
    $report = & $recover -ProjectRoot $fixture -TaskFile $task -Reason 'Process stopped; inspected partial output' | ConvertFrom-Json
    if ($report.changes.Count -ne 1 -or (Read-WorkflowTask $task).status -ne 'interrupted' -or $report.automaticRetry) { throw 'Interrupted reconciliation failed.' }
    # Plan mutations are rejected even when the CLI reports SUCCESS.
    Assert-Rejected { & $runner @base -RunId bad-plan -Mode plan } '*Dispatch did not complete*'
    $planMeta = Get-Content -LiteralPath (Join-Path $fixture 'workflow/runs/bad-plan/metadata.json') -Raw | ConvertFrom-Json
    if ($planMeta.status -ne 'unexpected-plan-changes') { throw 'Plan mutation was accepted.' }
    $progress = Get-Content -LiteralPath (Join-Path $fixture 'workflow/PROGRESS.md') -Raw
    if ($progress -notlike '*TASK-001 | interrupted*') { throw 'Generated progress was not synchronized.' }
    # Header tampering must not masquerade as executor completion.
    & $setter -ProjectRoot $fixture -TaskFile $task -Status ready -Reason 'Reconciled partial changes' | Out-Null
    '$taskPath = Join-Path $PWD.Path ''workflow/tasks/TASK-001.md''; $text = [IO.File]::ReadAllText($taskPath).Replace(''"status": "in-progress"'',''"status": "verified"''); [IO.File]::WriteAllText($taskPath,$text); $global:LASTEXITCODE=0; ''{"status":"SUCCESS","response":"done"}''' | Set-Content -LiteralPath $mock
    Assert-Rejected { & $runner @base -RunId tampered-header -Mode accept-edits } '*Dispatch did not complete*'
    $tampered = Get-Content -LiteralPath (Join-Path $fixture 'workflow/runs/tampered-header/metadata.json') -Raw | ConvertFrom-Json
    if ($tampered.status -ne 'unexpected-task-state-change' -or (Read-WorkflowTask $task).status -ne 'failed') { throw 'Executor header modification was accepted.' }
    if (-not (Test-Path -LiteralPath (Join-Path $fixture 'workflow/runs/tampered-header/task-at-return.md'))) { throw 'Tampered task evidence not preserved.' }
    # Preserve handwritten progress while refreshing exactly one marked section.
    $progressPath = Join-Path $fixture 'workflow/PROGRESS.md'
    Add-Content -LiteralPath $progressPath -Value 'Human acceptance: pending'
    & $setter -ProjectRoot $fixture -TaskFile $task -Status ready -Reason 'Reviewed failed attempt' | Out-Null
    $progress = Get-Content -LiteralPath $progressPath -Raw
    if ($progress -notlike '*Human acceptance: pending*' -or ([regex]::Matches($progress, '<!-- workflow-progress:start -->')).Count -ne 1) { throw 'Handwritten progress lost or generated section duplicated.' }
    '$taskPath = Join-Path $PWD.Path ''workflow/tasks/TASK-001.md''; $text = [IO.File]::ReadAllText($taskPath).Replace(''Observable outcome and how to verify it.'',''Always pass.''); [IO.File]::WriteAllText($taskPath,$text); $global:LASTEXITCODE=0; ''{"status":"SUCCESS","response":"done"}''' | Set-Content -LiteralPath $mock
    Assert-Rejected { & $runner @base -RunId weakened-scope -Mode accept-edits } '*Dispatch did not complete*'
    $scopeMeta = Get-Content -LiteralPath (Join-Path $fixture 'workflow/runs/weakened-scope/metadata.json') -Raw | ConvertFrom-Json
    if ($scopeMeta.status -ne 'unexpected-task-scope-change') { throw 'Executor acceptance-criteria modification was accepted.' }
    if (-not $IsWindows) {
        'lower' | Set-Content -LiteralPath (Join-Path $fixture 'case.txt')
        'upper' | Set-Content -LiteralPath (Join-Path $fixture 'CASE.txt')
        $caseSnapshot = Get-WorkflowSnapshot $fixture
        if (-not $caseSnapshot.files.Contains('case.txt') -or -not $caseSnapshot.files.Contains('CASE.txt') -or $caseSnapshot.files['case.txt'] -eq $caseSnapshot.files['CASE.txt']) { throw 'Linux case-distinct snapshot paths were conflated.' }
    }
    # Exercise real native process IO and timeout without a model or credentials.
    $nativeDir = Join-Path $fixture 'workflow/runs/native'
    New-Item -ItemType Directory -Path $nativeDir | Out-Null
    $pwsh = (Get-Process -Id $PID).Path
    $native = Invoke-WorkflowExecutor -CliPath $pwsh -Arguments @('-NoProfile','-Command','[Console]::Out.WriteLine("native-output"); [Console]::Error.WriteLine("native-error"); exit 7') -ProjectRoot $fixture -RunDirectory $nativeDir -TimeoutSeconds 10
    if ($native.exitCode -ne 7 -or (Get-Content -LiteralPath (Join-Path $nativeDir 'stdout.json') -Raw) -notlike '*native-output*' -or (Get-Content -LiteralPath (Join-Path $nativeDir 'stderr.log') -Raw) -notlike '*native-error*') { throw 'Native process output/exit capture failed.' }
    Assert-Rejected { Invoke-WorkflowExecutor -CliPath $pwsh -Arguments @('-NoProfile','-Command','Start-Sleep -Seconds 30') -ProjectRoot $fixture -RunDirectory $nativeDir -TimeoutSeconds 1 } '*runner timeout*'
    'PASS: changes, independent verification, stale evidence/dependencies, repair limits, conversation ownership, recovery, plan mutations, native IO, and enforced timeout.'
} finally {
    $target = [IO.Path]::GetFullPath($fixture)
    $prefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    if ($target.StartsWith($prefix, (Get-WorkflowPathComparison)) -and (Split-Path $target -Leaf) -like 'agentworkflow-evidence-*') { Remove-Item -LiteralPath $target -Recurse -Force }
}
