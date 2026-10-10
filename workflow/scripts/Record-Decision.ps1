#requires -Version 7.2
param([Parameter(Mandatory)][string]$ProjectRoot, [Parameter(Mandatory)][string]$InputFile)
$ErrorActionPreference='Stop'
foreach ($file in @('Platform.ps1','Task-State.ps1','Evidence.ps1','Workflow-Plan.ps1')) { . (Join-Path $PSScriptRoot $file) }
$root=(Resolve-Path -LiteralPath $ProjectRoot).Path
$record=Get-Content -LiteralPath $InputFile -Raw | ConvertFrom-Json -AsHashtable
if ($record.schemaVersion -ne 1 -or $record.decisionId -notmatch '^ADR-[A-Za-z0-9_-]+$' -or $record.status -notin @('proposed','accepted','superseded') -or $record.taskIds -isnot [array] -or -not $record.taskIds.Count) { throw 'Invalid decision record.' }
foreach ($id in $record.taskIds) { if ($id -notmatch '^TASK-[A-Za-z0-9_-]+$') { throw 'Invalid decision task linkage.' } }
foreach ($field in @('title','context','decision','alternatives','consequences','author')) { if ([string]::IsNullOrWhiteSpace($record[$field])) { throw "Decision requires $field." } }
if ($record.status -ne 'proposed' -and [string]::IsNullOrWhiteSpace($record.approvalReference)) { throw 'Accepted/superseded decisions require an explicit approval reference.' }
$directory=Resolve-WorkflowLocalPath $root 'workflow/decisions'
$runs=Resolve-WorkflowLocalPath $root 'workflow/runs'
New-Item -ItemType Directory -Path $runs -Force | Out-Null
$lock=[IO.File]::Open((Join-Path $runs 'active.lock'),[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::Write,[IO.FileShare]::None)
try {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $path=Join-Path $directory "$($record.decisionId).json"
    if (Test-Path -LiteralPath $path) { throw 'Decision IDs are immutable. Record a new decision with supersedes pointing to the earlier ID.' }
    $record['recordedUtc']=[DateTime]::UtcNow.ToString('o')
    Write-WorkflowJson $path $record
    @{file=[IO.Path]::GetRelativePath($root,$path).Replace('\','/'); hash=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash} | ConvertTo-Json
} finally { $lock.Dispose() }
$global:LASTEXITCODE=0
