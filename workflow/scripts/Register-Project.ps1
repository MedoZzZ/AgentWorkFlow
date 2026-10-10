#requires -Version 7.2
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_-]+$')][string]$Id,
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Path,
    [ValidateSet('active','archived')][string]$Status='active'
)
$ErrorActionPreference='Stop'
foreach ($file in @('Platform.ps1','Evidence.ps1','Workflow-Plan.ps1')) { . (Join-Path $PSScriptRoot $file) }
if ($Id -eq 'local' -or [string]::IsNullOrWhiteSpace($Name)) { throw 'Use a non-reserved project ID and name.' }
$root=(Resolve-Path -LiteralPath $ProjectRoot).Path
$target=(Resolve-Path -LiteralPath $Path).Path
if (-not (Test-Path -LiteralPath (Join-Path $target 'workflow') -PathType Container)) { throw 'Registered project must contain a workflow directory.' }
$registryPath=Resolve-WorkflowLocalPath $root 'workflow/projects.json'
$runs=Resolve-WorkflowLocalPath $root 'workflow/runs'
New-Item -ItemType Directory -Path $runs -Force | Out-Null
$lock=[IO.File]::Open((Join-Path $runs 'active.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::Write,[IO.FileShare]::None)
try {
    $registry=if (Test-Path -LiteralPath $registryPath) { Get-Content -LiteralPath $registryPath -Raw | ConvertFrom-Json -AsHashtable } else { @{schemaVersion=1; projects=@()} }
    if ($registry.schemaVersion -ne 1 -or $registry.projects -isnot [array]) { throw 'Invalid project registry.' }
    foreach ($entry in $registry.projects) {
        if ($entry.id -cne $Id -and [string]::Equals($entry.root,$target,(Get-WorkflowPathComparison))) { throw 'Project path is already registered with another ID.' }
    }
    $registry.projects=@($registry.projects | Where-Object id -CNE $Id)
    $registry.projects+=@{id=$Id; name=$Name; root=$target; status=$Status; registeredUtc=[DateTime]::UtcNow.ToString('o')}
    Write-WorkflowJson $registryPath $registry
    $registry | ConvertTo-Json -Depth 10
} finally { $lock.Dispose() }
$global:LASTEXITCODE=0
