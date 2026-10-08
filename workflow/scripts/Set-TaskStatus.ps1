#requires -Version 7.2
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][string]$TaskFile,
    [Parameter(Mandatory)][string]$Status,
    [Parameter(Mandatory)][string]$Reason
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Platform.ps1')
. (Join-Path $PSScriptRoot 'Task-State.ps1')
. (Join-Path $PSScriptRoot 'Evidence.ps1')
. (Join-Path $PSScriptRoot 'Progress.ps1')
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$path = (Resolve-Path -LiteralPath $TaskFile).Path
$prefix = $root.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
if (-not $path.StartsWith($prefix, (Get-WorkflowPathComparison))) { throw 'Task must be inside the project directory.' }
$runs = Join-Path $root 'workflow/runs'
New-Item -ItemType Directory -Path $runs -Force | Out-Null
$handle = [IO.File]::Open((Join-Path $runs 'active.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::Write, [IO.FileShare]::None)
try {
    $data = Read-WorkflowTask -Path $path
    if ($Status -eq 'in-progress') { throw 'Only the runner starts implementation attempts.' }
    if ($Status -eq 'verified') { throw 'Use Record-Verification.ps1 with independent structured evidence to mark verified.' }
    if ($Status -eq 'ready') { Assert-WorkflowTaskReady -ProjectRoot $root -TaskPath $path -Data $data }
    Set-WorkflowTaskTransition -Path $path -Data $data -Status $Status -Reason $Reason
    Sync-WorkflowProgress $root
    $data | ConvertTo-Json -Depth 20
} finally { $handle.Dispose() }
