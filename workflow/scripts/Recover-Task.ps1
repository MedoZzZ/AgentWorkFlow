#requires -Version 7.2
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][string]$TaskFile,
    [Parameter(Mandatory)][string]$Reason
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Platform.ps1')
. (Join-Path $PSScriptRoot 'Task-State.ps1')
. (Join-Path $PSScriptRoot 'Evidence.ps1')
. (Join-Path $PSScriptRoot 'Progress.ps1')
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$task = (Resolve-Path -LiteralPath $TaskFile).Path
$prefix = $root.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
if (-not $task.StartsWith($prefix, (Get-WorkflowPathComparison))) { throw 'Task must be inside the project directory.' }
if ([string]::IsNullOrWhiteSpace($Reason)) { throw 'Recovery requires an inspection reason.' }
$runs = Join-Path $root 'workflow/runs'
$handle = [IO.File]::Open((Join-Path $runs 'active.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::Write, [IO.FileShare]::None)
try {
    $data = Read-WorkflowTask $task
    if ($data.status -ne 'in-progress' -or -not $data.attempts.Count) { throw 'Recovery requires an abandoned in-progress attempt.' }
    $attempt = $data.attempts[-1]
    if ($attempt.runId -notmatch '^[A-Za-z0-9_-]+$') { throw 'Invalid recovery Run ID.' }
    $run = Join-Path $runs $attempt.runId
    $metaPath = Join-Path $run 'metadata.json'
    $metadata = if (Test-Path -LiteralPath $metaPath) { Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json -AsHashtable } else { $null }
    if ($metadata.executorProcessId) {
        $executor = Get-Process -Id $metadata.executorProcessId -ErrorAction SilentlyContinue
        if ($executor) {
            $recordedStart = ([DateTime]$metadata.executorStartedUtc).ToUniversalTime()
            if ([Math]::Abs(($executor.StartTime.ToUniversalTime() - $recordedStart).TotalSeconds) -lt 1) { throw 'Executor is still running. Stop or wait for it before reconciling the task.' }
        }
    }
    $snapshot = Get-WorkflowSnapshot $root
    $baseline = Get-Content -LiteralPath (Join-Path $run 'before.json') -Raw | ConvertFrom-Json -AsHashtable
    $report = @{taskId=$data.taskId; runId=$attempt.runId; reason=$Reason; timestampUtc=[DateTime]::UtcNow.ToString('o'); current=$snapshot; changes=(Compare-WorkflowSnapshot $baseline $snapshot); outcome='interrupted'; automaticRetry=$false}
    Write-WorkflowJson (Join-Path $run "recovery-$([guid]::NewGuid().ToString('N')).json") $report
    if ($metadata) {
        $metadata['status'] = 'interrupted'; $metadata['outcome'] = 'interrupted'; $metadata['recoveredUtc'] = $report.timestampUtc
        Write-WorkflowJson $metaPath $metadata
    }
    $data.attempts[-1]['finishedUtc'] = $report.timestampUtc
    $data.attempts[-1]['outcome'] = 'interrupted'
    Set-WorkflowTaskTransition $task $data interrupted "Recovery inspection: $Reason; partial changes recorded in $run" $attempt.runId $attempt.attemptId
    Sync-WorkflowProgress $root
    $report | ConvertTo-Json -Depth 20
} finally { $handle.Dispose() }
