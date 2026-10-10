#requires -Version 7.2
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][string]$TaskFile,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_-]+$')][string]$RunId,
    [ValidateSet('plan','accept-edits')][string]$Mode,
    [ValidateRange(10,3600)][int]$TimeoutSeconds,
    [string]$ConversationId,
    [string]$CliPath,
    [ValidatePattern('^[a-zA-Z0-9._-]+$')][string]$Model,
    [ValidateRange(0,20)][int]$MaxRepairAttempts = 3,
    [switch]$Stream,
    [string]$ConfigPath,
    [string]$RepairFile,
    [string[]]$AllowedFiles,
    [ValidatePattern('^[A-Za-z0-9_-]+$')][string]$WorkflowId,
    [scriptblock]$OnAttemptStarted
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Platform.ps1')
. (Join-Path $PSScriptRoot 'Task-State.ps1')
. (Join-Path $PSScriptRoot 'Evidence.ps1')
. (Join-Path $PSScriptRoot 'Antigravity-Adapter.ps1')
. (Join-Path $PSScriptRoot 'Progress.ps1')
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
if (-not $ConfigPath) { $ConfigPath = Join-Path $root 'workflow/config.json' }
$config = & (Join-Path $PSScriptRoot 'Read-Config.ps1') -ConfigPath $ConfigPath
if (-not $PSBoundParameters.ContainsKey('Mode')) { $Mode = $config.antigravity.mode }
if (-not $PSBoundParameters.ContainsKey('TimeoutSeconds')) { $TimeoutSeconds = $config.antigravity.timeoutSeconds }
if (-not $PSBoundParameters.ContainsKey('Model')) { $Model = $config.antigravity.model }
if (-not $CliPath -and $config.antigravity.cliPath) { $CliPath = $config.antigravity.cliPath }
$task = (Resolve-Path -LiteralPath $TaskFile).Path
$prefix = $root.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
if (-not $task.StartsWith($prefix, (Get-WorkflowPathComparison))) { throw 'Task must be inside the project directory.' }
$CliPath = Resolve-WorkflowCli -ConfiguredPath $CliPath
if (-not (Test-Path -LiteralPath $CliPath -PathType Leaf)) { throw 'Antigravity CLI was not found.' }
$CliPath = (Resolve-Path -LiteralPath $CliPath).Path
if ($IsLinux -and [IO.Path]::GetExtension($CliPath) -ne '.ps1' -and -not (Test-WorkflowExecutable $CliPath)) { throw 'Linux Antigravity CLI is not executable. Install the native CLI or grant its executable permission.' }
$runDir = Join-Path $root "workflow/runs/$RunId"
New-Item -ItemType Directory -Path (Split-Path $runDir) -Force | Out-Null
$projectLock = $null
$lock = $null
$metadata = $null
$metaPath = $null
$taskData = $null
$attemptId = $null
# OS-held lock prevents different run IDs from editing the same project at once.
try { $projectLock = [IO.File]::Open((Join-Path $root 'workflow/runs/active.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::Write, [IO.FileShare]::None) }
catch { throw 'Another dispatch is active for this project. Wait for it to finish before starting another.' }
try {
foreach ($file in (Get-ChildItem -LiteralPath (Split-Path $runDir) -Filter metadata.json -Recurse -File)) {
    $previousRun = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    if ($previousRun.status -eq 'running') { throw "An unreconciled run remains: $($previousRun.runId). Inspect its process and evidence before dispatching." }
}
$taskData = Read-WorkflowTask -Path $task -AllowLegacy
if ($taskData -and $Mode -eq 'accept-edits') {
    if ($taskData.status -notin @('ready','needs-fix')) { throw "Task cannot execute from status: $($taskData.status)" }
    Assert-WorkflowTaskReady -ProjectRoot $root -TaskPath $task -Data $taskData
    if ($taskData.attempts.Count -ge (1 + $MaxRepairAttempts)) { throw 'Repair attempt limit reached. Diagnose and obtain approval for a revised task before continuing.' }
    if ($ConversationId) {
        $knownConversation = $false
        foreach ($file in (Get-ChildItem -LiteralPath (Split-Path $runDir) -Filter metadata.json -Recurse -File)) {
            $previous = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
            if ($previous.taskId -eq $taskData.taskId -and $previous.conversationId -eq $ConversationId) { $knownConversation = $true }
        }
        if (-not $knownConversation) { throw 'Conversation ID is not recorded for this managed task.' }
    }
}
# Atomic directory creation refuses duplicate run IDs, including concurrent launches.
if (-not [IO.Directory]::Exists($runDir)) {
    $claim = Join-Path (Split-Path $runDir) "$RunId.lock"
    $lock = [IO.File]::Open($claim, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
} else { throw 'Run ID already exists. Inspect its evidence before assigning a new run ID.' }
    New-Item -ItemType Directory -Path $runDir | Out-Null
    $before = Get-WorkflowSnapshot -ProjectRoot $root
    Write-WorkflowJson -Path (Join-Path $runDir 'before.json') -Value $before
    & (Join-Path $PSScriptRoot 'Preflight.ps1') -ProjectRoot $root -ConfigPath $ConfigPath | Set-Content -LiteralPath (Join-Path $runDir 'preflight.json') -Encoding utf8
    $config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runDir 'config.json') -Encoding utf8
    $instruction = if ($Mode -eq 'plan') { 'Read-only: do not edit files or execute shell commands. Read the task and return the requested report.' } else { 'Execute only the assigned task. Record actual checks and evidence in its Executor result section. Mark ready-for-verification only; never verified. Preserve existing user changes.' }
    if ($taskData) { $instruction += ' The runner owns the workflow-task JSON header and Status line: do not edit them. Report your result in the Executor result section.' }
    $prompt = "Project root: $root`nTask file: $task`n$instruction`nRead workflow/ANTIGRAVITY-HANDOFF.md if present, relevant project instructions, and linked specifications. Report missing access explicitly."
    if ($AllowedFiles) { $prompt += "`nApproved editable files (exact paths): $($AllowedFiles -join ', '). Stop and report if other edits are needed." }
    if ($RepairFile) {
        $repairInstructions = [IO.File]::ReadAllText((Resolve-Path -LiteralPath $RepairFile).Path)
        if ([string]::IsNullOrWhiteSpace($repairInstructions)) { throw 'Repair instructions cannot be empty.' }
        $prompt += "`nFocused coordinator repair findings:`n$repairInstructions`nPreserve the original requirements, user edits, and prior attempt evidence."
        $repairInstructions | Set-Content -LiteralPath (Join-Path $runDir 'repair.txt') -Encoding utf8
    }
    $prompt | Set-Content -LiteralPath (Join-Path $runDir 'prompt.txt') -Encoding utf8
    $metadata = [ordered]@{ runId=$RunId; task=$task; mode=$Mode; model=$Model; timeoutSeconds=$TimeoutSeconds; cliPath=$CliPath; configPath=(Resolve-Path -LiteralPath $ConfigPath).Path; startedUtc=[DateTime]::UtcNow.ToString('o'); status='running'; conversationId=$ConversationId; verification='pending' }
    $metaPath = Join-Path $runDir 'metadata.json'
    $metadata['taskManagement'] = if ($taskData) { 'managed' } else { 'legacy-unmanaged' }
    $metadata['maxRepairAttempts'] = $MaxRepairAttempts
    $metadata['processId'] = $PID
    $metadata['executorIdentity'] = 'antigravity'
    $metadata['runnerStartedUtc'] = (Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')
    if ($WorkflowId) { $metadata['workflowId'] = $WorkflowId }
    if ($AllowedFiles) { $metadata['allowedFiles'] = $AllowedFiles }
    $metadata['outcome'] = 'running'
    $metadata['outputFormat'] = if ($Stream) { 'stream-json' } else { 'json' }
    if ($taskData) { $metadata['taskId'] = $taskData.taskId }
    if ($taskData -and $Mode -eq 'accept-edits') {
        $attemptId = [guid]::NewGuid().ToString('N')
        $metadata['attemptId'] = $attemptId
        $taskData.attempts += @{attemptId=$attemptId; runId=$RunId; startedUtc=$metadata.startedUtc}
        Set-WorkflowTaskTransition -Path $task -Data $taskData -Status 'in-progress' -Reason "Dispatch: workflow/runs/$RunId" -RunId $RunId -AttemptId $attemptId
    }
    Write-WorkflowJson $metaPath $metadata
    if ($attemptId -and $OnAttemptStarted) { & $OnAttemptStarted $attemptId $RunId }
    $taskFileHash = (Get-FileHash -LiteralPath $task -Algorithm SHA256).Hash
    $taskScopeHash = Get-WorkflowTaskScopeHash $task
    Copy-Item -LiteralPath $task -Destination (Join-Path $runDir 'task-at-dispatch.md')
    $otherTasks = [Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
    $taskDirectory = Join-Path $root 'workflow/tasks'
    if (Test-Path -LiteralPath $taskDirectory) {
        foreach ($file in Get-ChildItem -LiteralPath $taskDirectory -File -Recurse) {
            if (-not [string]::Equals($file.FullName,$task,(Get-WorkflowPathComparison))) { $otherTasks[$file.FullName] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash }
        }
    }
    $controllerStatePath = if ($WorkflowId) { Join-Path $root "workflow/runs/_workflows/$WorkflowId/state.json" } else { $null }
    $controllerStateHash = if ($controllerStatePath -and (Test-Path -LiteralPath $controllerStatePath)) { (Get-FileHash -LiteralPath $controllerStatePath -Algorithm SHA256).Hash } else { $null }
    $taskHeader = if ($taskData) { [regex]::Match([IO.File]::ReadAllText($task), $script:TaskHeaderPattern).Value } else { $null }
    $arguments = @('-p',$prompt,'--mode',$Mode,'--model',$Model,'--output-format',$metadata.outputFormat,'--print-timeout',"${TimeoutSeconds}s")
    if ($ConversationId) { $arguments += @('--conversation',$ConversationId) }
    $execution = Invoke-WorkflowExecutor -CliPath $CliPath -Arguments $arguments -ProjectRoot $root -RunDirectory $runDir -TimeoutSeconds $TimeoutSeconds -Stream:$Stream -OnStarted {
        param($executorPid, $executorStartedUtc)
        $metadata['executorProcessId'] = $executorPid
        $metadata['executorStartedUtc'] = $executorStartedUtc
        Write-WorkflowJson $metaPath $metadata
    } -OnEvent {
        param($cliEvent)
        if ($cliEvent.event -eq 'init' -and $cliEvent.conversation_id) {
            $metadata.conversationId = $cliEvent.conversation_id
            Write-WorkflowJson $metaPath $metadata
        }
    }
    $exitCode = $execution.exitCode
    if ($execution.conversationId) { $metadata.conversationId = $execution.conversationId }
    Copy-Item -LiteralPath $task -Destination (Join-Path $runDir 'task-at-return.md')
    $metadata['exitCode'] = $exitCode
    $metadata['finishedUtc'] = [DateTime]::UtcNow.ToString('o')
    $result = Read-WorkflowExecutorResult -Path (Join-Path $runDir 'stdout.json') -ExitCode $exitCode
    $metadata.status = $result.status
    $metadata['executorStatus'] = $result.executorStatus
    if ($result.conversationId) { $metadata.conversationId = $result.conversationId }
    if ($result.deniedActions) { $metadata['deniedActions'] = $result.deniedActions }
    $after = Get-WorkflowSnapshot -ProjectRoot $root
    Write-WorkflowJson -Path (Join-Path $runDir 'after.json') -Value $after
    $changes = Compare-WorkflowSnapshot -Before $before -After $after
    Write-WorkflowJson -Path (Join-Path $runDir 'changes.json') -Value @{changes=$changes}
    if ($Mode -eq 'plan' -and ($changes.Count -or (Get-FileHash -LiteralPath $task -Algorithm SHA256).Hash -ne $taskFileHash)) { $metadata.status = 'unexpected-plan-changes' }
    if ($taskHeader -and [regex]::Match([IO.File]::ReadAllText($task), $script:TaskHeaderPattern).Value -cne $taskHeader) { $metadata.status = 'unexpected-task-state-change' }
    elseif ($taskData -and (Get-WorkflowTaskScopeHash $task) -ne $taskScopeHash) { $metadata.status = 'unexpected-task-scope-change' }
    if ($AllowedFiles -and @($changes | Where-Object { $_.path -cnotin $AllowedFiles }).Count) { $metadata.status = 'unexpected-file-changes' }
    $returnedTasks = [Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
    if (Test-Path -LiteralPath $taskDirectory) {
        foreach ($file in Get-ChildItem -LiteralPath $taskDirectory -File -Recurse) {
            if (-not [string]::Equals($file.FullName,$task,(Get-WorkflowPathComparison))) { $returnedTasks[$file.FullName] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash }
        }
    }
    if ($otherTasks.Count -ne $returnedTasks.Count) { $metadata.status = 'unexpected-task-state-change' }
    foreach ($file in $otherTasks.Keys) { if ($otherTasks[$file] -ne $returnedTasks[$file]) { $metadata.status = 'unexpected-task-state-change' } }
    if ($controllerStateHash -and (-not (Test-Path -LiteralPath $controllerStatePath) -or (Get-FileHash -LiteralPath $controllerStatePath -Algorithm SHA256).Hash -ne $controllerStateHash)) { $metadata.status = 'unexpected-task-state-change' }
    $metadata['outcome'] = if ($metadata.status -eq 'SUCCESS') { if ($Mode -eq 'plan') { 'planned' } else { 'ready-for-verification' } } else { $metadata.status }
    Write-WorkflowJson $metaPath $metadata
    if ($exitCode -ne 0 -or $metadata.status -ne 'SUCCESS') { throw "Dispatch did not complete successfully. Inspect $runDir. Do not retry automatically." }
    if ($attemptId) {
        $taskData.attempts[-1]['finishedUtc'] = $metadata.finishedUtc
        $taskData.attempts[-1]['outcome'] = 'ready-for-verification'
        Set-WorkflowTaskTransition -Path $task -Data $taskData -Status 'ready-for-verification' -Reason "Executor completed; independent verification pending: workflow/runs/$RunId" -RunId $RunId -AttemptId $attemptId
    }
    $metadata | ConvertTo-Json -Depth 20
} catch {
    $dispatchError = $_
    if ($metadata -and $metaPath) {
        if ($dispatchError.Exception -is [TimeoutException]) { $metadata.status = 'interrupted' }
        elseif ($dispatchError.Exception.Message -like 'Invalid streaming output*') { $metadata.status = 'invalid-output' }
        elseif ($metadata.status -in @('running','SUCCESS')) { $metadata.status = 'failed' }
        $metadata['outcome'] = $metadata.status
        $metadata['error'] = $_.Exception.Message
        $metadata['finishedUtc'] = [DateTime]::UtcNow.ToString('o')
        Write-WorkflowJson $metaPath $metadata
    }
    if ($attemptId -and $taskData.status -eq 'in-progress') {
        $failureState = if ($metadata.status -eq 'blocked-permissions') { 'blocked' } elseif ($metadata.status -eq 'interrupted') { 'interrupted' } else { 'failed' }
        $taskData.attempts[-1]['finishedUtc'] = $metadata.finishedUtc
        $taskData.attempts[-1]['outcome'] = $failureState
        try { Set-WorkflowTaskTransition -Path $task -Data $taskData -Status $failureState -Reason $dispatchError.Exception.Message -RunId $RunId -AttemptId $attemptId }
        catch { $metadata['taskStateError'] = $_.Exception.Message; Write-WorkflowJson $metaPath $metadata }
    }
    throw $dispatchError
} finally {
    if ($metadata -and (Test-Path -LiteralPath $task) -and -not (Test-Path -LiteralPath (Join-Path $runDir 'task-at-return.md'))) { Copy-Item -LiteralPath $task -Destination (Join-Path $runDir 'task-at-return.md') }
    if ($metadata -and $metaPath -and -not (Test-Path -LiteralPath (Join-Path $runDir 'after.json'))) {
        try {
            $after = Get-WorkflowSnapshot -ProjectRoot $root
            Write-WorkflowJson -Path (Join-Path $runDir 'after.json') -Value $after
            Write-WorkflowJson -Path (Join-Path $runDir 'changes.json') -Value @{changes=(Compare-WorkflowSnapshot $before $after)}
        } catch { $metadata['evidenceError'] = $_.Exception.Message; Write-WorkflowJson -Path $metaPath -Value $metadata }
    }
    if ($taskData -and $metadata) {
        try { Sync-WorkflowProgress $root } catch { $metadata['progressError'] = $_.Exception.Message; Write-WorkflowJson $metaPath $metadata }
    }
    if ($lock) { $lock.Dispose() }
    if ($projectLock) { $projectLock.Dispose() }
}
# SUCCESS is an executor result, not coordinator verification. Permission denials
# can occur even with SUCCESS; inspect stderr and validate the actual changes.
$global:LASTEXITCODE=0
