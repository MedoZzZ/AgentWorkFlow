#requires -Version 7.2
param([Parameter(Mandatory)][string]$ProjectRoot, [string]$ConfigPath)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
if (-not $ConfigPath) { $ConfigPath = Join-Path $root 'workflow/config.json' }
$config = & (Join-Path $PSScriptRoot 'Read-Config.ps1') -ConfigPath $ConfigPath
. (Join-Path $PSScriptRoot 'Platform.ps1')
$cliPath = Resolve-WorkflowCli -ConfiguredPath $config.antigravity.cliPath
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
    operatingSystem = [Runtime.InteropServices.RuntimeInformation]::OSDescription
    powerShellVersion = $PSVersionTable.PSVersion.ToString()
    projectRoot = $root
    configPath = (Resolve-Path -LiteralPath $ConfigPath).Path
    configuredModel = $config.antigravity.model
    cliPath = $cliPath
    cliAvailable = (Test-Path -LiteralPath $cliPath -PathType Leaf)
    cliExecutable = (Test-WorkflowExecutable $cliPath)
    dashboardNodeAvailable = [bool](Get-Command node -CommandType Application -ErrorAction SilentlyContinue)
    gitRepository = $gitAvailable
    baselineRevision = $head
    existingChanges = $changes
    runtimeCommands = $runtimes
    manifests = @($files | Where-Object { Test-Path -LiteralPath (Join-Path $root $_) })
    workflowPresent = (Test-Path -LiteralPath (Join-Path $root 'workflow/LIFECYCLE.md'))
    baselineChecks = 'Not run: select the actual project commands in CI.md before implementation.'
} | ConvertTo-Json -Depth 5
$global:LASTEXITCODE = 0
