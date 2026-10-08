param([Parameter(Mandatory)][string]$ProjectRoot, [string]$ConfigPath)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
if (-not $ConfigPath) { $ConfigPath = Join-Path $root 'workflow\config.json' }
$config = & (Join-Path $PSScriptRoot 'Read-Config.ps1') -ConfigPath $ConfigPath
$cli = Get-Command agy -ErrorAction SilentlyContinue
$cliPath = if ($cli) { $cli.Source } else { Join-Path $env:LOCALAPPDATA 'agy\bin\agy.exe' }
if ($config.antigravity.cliPath) { $cliPath = $config.antigravity.cliPath }
$git = Get-Command git -ErrorAction SilentlyContinue
$head = $null; $changes = @(); $gitAvailable = $false
if ($git) {
    $headOutput = & git -C $root rev-parse HEAD 2>$null
    if ($LASTEXITCODE -eq 0) {
        $head = "$headOutput"; $gitAvailable = $true
        $changes = @(& git -C $root status --porcelain)
    }
}
$runtimes = [ordered]@{}
foreach ($name in $config.preflight.runtimeCommands) {
    $command = Get-Command $name -ErrorAction SilentlyContinue
    $runtimes[$name] = if ($command) { $command.Source } else { $null }
}
$files = $config.preflight.manifestFiles
[ordered]@{
    projectRoot = $root
    configPath = (Resolve-Path -LiteralPath $ConfigPath).Path
    configuredModel = $config.antigravity.model
    cliPath = $cliPath
    cliAvailable = (Test-Path -LiteralPath $cliPath -PathType Leaf)
    gitRepository = $gitAvailable
    baselineRevision = $head
    existingChanges = $changes
    runtimeCommands = $runtimes
    manifests = @($files | Where-Object { Test-Path -LiteralPath (Join-Path $root $_) })
    workflowPresent = (Test-Path -LiteralPath (Join-Path $root 'workflow\LIFECYCLE.md'))
    baselineChecks = 'Not run: select the actual project commands in CI.md before implementation.'
} | ConvertTo-Json -Depth 5
