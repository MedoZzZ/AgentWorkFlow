#requires -Version 7.2
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][string]$PlanFile,
    [Parameter(Mandatory)][string]$TaskId,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_-]+$')][string]$RunId,
    [Parameter(Mandatory)][string]$DeadlineUtc
)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Platform.ps1')
. (Join-Path $PSScriptRoot 'Task-State.ps1')
. (Join-Path $PSScriptRoot 'Evidence.ps1')
. (Join-Path $PSScriptRoot 'Workflow-Plan.ps1')
$root=(Resolve-Path -LiteralPath $ProjectRoot).Path
$plan=Read-WorkflowPlan $root $PlanFile
$entry=@($plan.tasks | Where-Object taskId -CEQ $TaskId)
if ($entry.Count -ne 1) { throw 'Check task must be approved.' }; $entry=$entry[0]
$taskPath=Resolve-WorkflowLocalPath $root $entry.file
$task=Read-WorkflowTask $taskPath
if ($task.status -ne 'ready-for-verification' -or $task.attempts[-1].runId -ne $RunId -or $entry.scopeHash -ne (Get-WorkflowTaskScopeHash $taskPath)) { throw 'Checks require the current approved implementation attempt.' }
$run=Join-Path $root "workflow/runs/$RunId"
$handle=[IO.File]::Open((Join-Path $root 'workflow/runs/active.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::Write,[IO.FileShare]::None)
try {
    $before=Get-WorkflowSnapshot $root
    $directory=Join-Path $run "checks/$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    Write-WorkflowJson (Join-Path $directory 'before.json') $before
    $processPath=Join-Path $run 'check-process.json'
    $processState=@{status='running'; processId=$PID; runnerStartedUtc=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o'); directory=[IO.Path]::GetRelativePath($root,$directory).Replace('\','/'); taskId=$TaskId; runId=$RunId; checks=@()}
    Write-WorkflowJson $processPath $processState
    $results=@(); $number=0
    foreach ($check in $entry.checks) {
        $number++; $status='unavailable'; $exitCode=$null; $errorMessage=$null
        $stdout=Join-Path $directory "$number.stdout.log"; $stderr=Join-Path $directory "$number.stderr.log"
        $remaining=[Math]::Floor((([DateTime]$DeadlineUtc).ToUniversalTime()-[DateTime]::UtcNow).TotalSeconds)
        if ($remaining -le 0) { throw 'Workflow duration exhausted before check execution.' }
        $timeout=[Math]::Min($remaining,$check.timeoutSeconds)
        $applicable=$check.platform -eq 'all' -or ($IsWindows -and $check.platform -eq 'windows') -or ($IsLinux -and $check.platform -eq 'linux')
        $process=$null
        try {
            if (-not $applicable) { $status='skipped'; $errorMessage='Check targets another platform.' }
            else {
                $command=Get-Command $check.executable -CommandType Application -ErrorAction Stop | Select-Object -First 1
                $start=[Diagnostics.ProcessStartInfo]::new(); $start.FileName=$command.Source
                $start.WorkingDirectory=if ($check.workingDirectory -eq '') { $root } else { Resolve-WorkflowLocalPath $root $check.workingDirectory -Directory }
                $start.UseShellExecute=$false; $start.CreateNoWindow=$true; $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
                foreach ($argument in $check.arguments) { $start.ArgumentList.Add($argument) }
                $process=[Diagnostics.Process]::new(); $process.StartInfo=$start
                $null=$process.Start()
                $processState['executorProcessId']=$process.Id
                $processState['executorStartedUtc']=$process.StartTime.ToUniversalTime().ToString('o')
                $processState['activeCheck']=$check.name
                Write-WorkflowJson $processPath $processState
                $outStream=[IO.File]::Create($stdout); $errStream=[IO.File]::Create($stderr)
                try {
                    $outCopy=$process.StandardOutput.BaseStream.CopyToAsync($outStream); $errCopy=$process.StandardError.BaseStream.CopyToAsync($errStream)
                    if (-not $process.WaitForExit([int]($timeout*1000))) { $process.Kill($true); $process.WaitForExit(); $errorMessage='Check timed out.' }
                    $outCopy.GetAwaiter().GetResult(); $errCopy.GetAwaiter().GetResult()
                    $exitCode=$process.ExitCode; $status=if ($exitCode -eq 0 -and -not $errorMessage) { 'passed' } else { 'failed' }
                } finally { $outStream.Dispose(); $errStream.Dispose() }
            }
        } catch { $errorMessage=$_.Exception.Message; $status='unavailable' }
        finally { if ($process) { try { if (-not $process.HasExited) { $process.Kill($true) } } catch {}; $process.Dispose() } }
        $results+=@{name=$check.name; required=$check.required; status=$status; exitCode=$exitCode; error=$errorMessage; evidence=[IO.Path]::GetRelativePath($root,$directory).Replace('\','/')+"/$number.stdout.log"; stderr=[IO.Path]::GetRelativePath($root,$directory).Replace('\','/')+"/$number.stderr.log"; executable=$check.executable; arguments=$check.arguments}
        $processState.checks=$results
        $processState['executorProcessId']=$null
        Write-WorkflowJson $processPath $processState
    }
    $after=Get-WorkflowSnapshot $root
    # Retain task edits across rechecks without attributing unrelated later edits to this check.
    $checkChanges=Compare-WorkflowSnapshot $before $after
    $changePath=Join-Path $run 'changes.json'
    $original=Get-Content -LiteralPath $changePath -Raw | ConvertFrom-Json -AsHashtable
    if (-not (Test-Path -LiteralPath (Join-Path $run 'executor-changes.json'))) { Write-WorkflowJson (Join-Path $run 'executor-changes.json') $original }
    $combined=[Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
    foreach ($change in $original.changes) { $combined[$change.path]=$change }
    foreach ($change in $checkChanges) { $combined[$change.path]=$change }
    $changes=@($combined.Values)
    Write-WorkflowJson $changePath @{changes=$changes}
    $unexpected=@($checkChanges | Where-Object { $_.path -cnotin $entry.allowedFiles })
    $result=@{schemaVersion=1; taskId=$TaskId; runId=$RunId; checks=$results; testedFingerprint=$after.fingerprint; taskScopeHash=(Get-WorkflowTaskScopeHash $taskPath); changes=$changes; unexpectedChanges=$unexpected; recordedUtc=[DateTime]::UtcNow.ToString('o')}
    Write-WorkflowJson (Join-Path $directory 'results.json') $result
    Write-WorkflowJson (Join-Path $run 'checks.json') $result
    $processState.status='finished'; $processState['finishedUtc']=[DateTime]::UtcNow.ToString('o')
    Write-WorkflowJson $processPath $processState
    $result | ConvertTo-Json -Depth 20
} finally {
    try {
        if ($processState -and $processState.status -eq 'running') {
            $processState.status='abandoned'; $processState['executorProcessId']=$null
            Write-WorkflowJson $processPath $processState
        }
    } finally { $handle.Dispose() }
}
$global:LASTEXITCODE=0
