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
    [string]$ConfigPath
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Platform.ps1')
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
$runDir = Join-Path $root "workflow/runs/$RunId"
New-Item -ItemType Directory -Path (Split-Path $runDir) -Force | Out-Null
$projectLock = $null
$lock = $null
$metadata = $null
$metaPath = $null
# OS-held lock prevents different run IDs from editing the same project at once.
try { $projectLock = [IO.File]::Open((Join-Path $root 'workflow/runs/active.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::Write, [IO.FileShare]::None) }
catch { throw 'Another dispatch is active for this project. Wait for it to finish before starting another.' }
try {
# Atomic directory creation refuses duplicate run IDs, including concurrent launches.
if (-not [IO.Directory]::Exists($runDir)) {
    $claim = Join-Path (Split-Path $runDir) "$RunId.lock"
    $lock = [IO.File]::Open($claim, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
} else { throw 'Run ID already exists. Inspect its evidence before assigning a new run ID.' }
    New-Item -ItemType Directory -Path $runDir | Out-Null
    & (Join-Path $PSScriptRoot 'Preflight.ps1') -ProjectRoot $root -ConfigPath $ConfigPath | Set-Content -LiteralPath (Join-Path $runDir 'preflight.json') -Encoding utf8
    $config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runDir 'config.json') -Encoding utf8
    $instruction = if ($Mode -eq 'plan') { 'Read-only: do not edit files or execute shell commands. Read the task and return the requested report.' } else { 'Execute only the assigned task. Record actual checks and evidence in its Executor result section. Mark ready-for-verification only; never verified. Preserve existing user changes.' }
    $prompt = "Project root: $root`nTask file: $task`n$instruction`nRead workflow/ANTIGRAVITY-HANDOFF.md if present, relevant project instructions, and linked specifications. Report missing access explicitly."
    $prompt | Set-Content -LiteralPath (Join-Path $runDir 'prompt.txt') -Encoding utf8
    $metadata = [ordered]@{ runId=$RunId; task=$task; mode=$Mode; model=$Model; timeoutSeconds=$TimeoutSeconds; cliPath=$CliPath; configPath=(Resolve-Path -LiteralPath $ConfigPath).Path; startedUtc=[DateTime]::UtcNow.ToString('o'); status='running'; conversationId=$ConversationId; verification='pending' }
    $metaPath = Join-Path $runDir 'metadata.json'
    $metadata | ConvertTo-Json | Set-Content -LiteralPath $metaPath -Encoding utf8
    $arguments = @('-p',$prompt,'--mode',$Mode,'--model',$Model,'--output-format','json','--print-timeout',"${TimeoutSeconds}s")
    if ($ConversationId) { $arguments += @('--conversation',$ConversationId) }
    Push-Location -LiteralPath $root
    try {
        & $CliPath @arguments 1> (Join-Path $runDir 'stdout.json') 2> (Join-Path $runDir 'stderr.log')
        $exitCode = $LASTEXITCODE
    } finally { Pop-Location }
    $metadata['exitCode'] = $exitCode
    $metadata['finishedUtc'] = [DateTime]::UtcNow.ToString('o')
    try {
        $result = Get-Content -LiteralPath (Join-Path $runDir 'stdout.json') -Raw | ConvertFrom-Json
        $metadata.status = $result.status
        $metadata.conversationId = $result.conversation_id
        if (@($result.denied_actions).Count -gt 0 -and $null -ne $result.denied_actions) {
            $metadata['executorStatus'] = $result.status
            $metadata.status = 'blocked-permissions'
            $metadata['deniedActions'] = $result.denied_actions
        } elseif ($result.status -eq 'SUCCESS' -and [string]::IsNullOrWhiteSpace([string]$result.response)) {
            $metadata.status = 'empty-response'
        }
    } catch { $metadata.status = 'invalid-output' }
    if ($exitCode -ne 0 -and $metadata.status -eq 'SUCCESS') {
        $metadata['executorStatus'] = 'SUCCESS'
        $metadata.status = 'failed'
    }
    $metadata | ConvertTo-Json | Set-Content -LiteralPath $metaPath -Encoding utf8
    $metadata | ConvertTo-Json
    if ($exitCode -ne 0 -or $metadata.status -ne 'SUCCESS') { throw "Dispatch did not complete successfully. Inspect $runDir. Do not retry automatically." }
} catch {
    if ($metadata -and $metaPath) {
        if ($metadata.status -eq 'running') { $metadata.status = 'failed' }
        $metadata['error'] = $_.Exception.Message
        $metadata['finishedUtc'] = [DateTime]::UtcNow.ToString('o')
        $metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $metaPath -Encoding utf8
    }
    throw
} finally {
    if ($lock) { $lock.Dispose() }
    if ($projectLock) { $projectLock.Dispose() }
}
# SUCCESS is an executor result, not coordinator verification. Permission denials
# can occur even with SUCCESS; inspect stderr and validate the actual changes.
