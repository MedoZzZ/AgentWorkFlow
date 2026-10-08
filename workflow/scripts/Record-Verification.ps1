#requires -Version 7.2
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][string]$TaskFile,
    [Parameter(Mandatory)][string]$EvidenceFile
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
$runs = Join-Path $root 'workflow/runs'
$handle = [IO.File]::Open((Join-Path $runs 'active.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::Write, [IO.FileShare]::None)
try {
    $data = Read-WorkflowTask $task
    if ($data.status -ne 'ready-for-verification') { throw 'Task is not ready for verification.' }
    $evidence = Get-Content -LiteralPath $EvidenceFile -Raw | ConvertFrom-Json -AsHashtable
    if ($evidence.schemaVersion -ne 1 -or $evidence.taskId -ne $data.taskId -or $evidence.runId -notmatch '^[A-Za-z0-9_-]+$') { throw 'Invalid verification identity/schema.' }
    $latest = $data.attempts[-1]
    if ($evidence.runId -ne $latest.runId) { throw 'Verification must reference the latest implementation attempt.' }
    if ($evidence.verdict -notin @('verified','needs-fix','blocked')) { throw 'Invalid verification verdict.' }
    foreach ($field in @('diffReviewed','testChangesReviewed','unexpectedChangesReviewed')) {
        if ($evidence[$field] -isnot [bool] -or -not $evidence[$field]) { throw "Verification requires $field." }
    }
    if ($evidence.checks -isnot [array] -or -not $evidence.checks.Count -or $evidence.acceptanceCriteria -isnot [array] -or -not $evidence.acceptanceCriteria.Count) { throw 'Verification requires checks and acceptance criteria.' }
    foreach ($check in (@($evidence.checks) + @($evidence.acceptanceCriteria))) {
        if ([string]::IsNullOrWhiteSpace($check.name) -or [string]::IsNullOrWhiteSpace($check.evidence) -or $check.status -notin @('passed','failed','skipped','unavailable') -or $check.required -isnot [bool]) { throw 'Invalid verification check/evidence.' }
        if ($evidence.verdict -eq 'verified' -and ($check.status -eq 'failed' -or ($check.required -and $check.status -ne 'passed'))) { throw 'Failed or incomplete required checks prevent verification.' }
    }
    $snapshot = Get-WorkflowSnapshot $root
    if ($evidence.testedFingerprint -ne $snapshot.fingerprint -or $evidence.taskScopeHash -ne (Get-WorkflowTaskScopeHash $task)) { throw 'Verification evidence is stale for the current files/task scope.' }
    if ($evidence.scope -isnot [array] -or -not $evidence.scope.Count) { throw 'Verification requires explicit file scope.' }
    $changes = Get-Content -LiteralPath (Join-Path $runs "$($latest.runId)/changes.json") -Raw | ConvertFrom-Json -AsHashtable
    foreach ($change in $changes.changes) {
        if ($change.path -cnotin $evidence.scope) { throw "Changed file is missing from verification scope: $($change.path)" }
    }
    $fileHashes = [Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
    foreach ($path in $evidence.scope) {
        if ($path -isnot [string] -or [string]::IsNullOrWhiteSpace($path) -or [IO.Path]::IsPathRooted($path) -or $path.Contains('\') -or '..' -in ($path -split '/') -or '.' -in ($path -split '/')) { throw 'Invalid verification scope path.' }
        if (-not $snapshot.files.Contains($path) -and $path -cnotin @($changes.changes | Where-Object kind -eq deleted | ForEach-Object path)) { throw "Verification scope file is absent or excluded: $path" }
        $fileHashes[$path] = $snapshot.files[$path]
    }
    $evidence['recordedUtc'] = [DateTime]::UtcNow.ToString('o')
    $evidence['testedRevision'] = $snapshot.revision
    $directory = Join-Path $runs "$($latest.runId)/verification"
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
    $recordPath = Join-Path $directory "$([guid]::NewGuid().ToString('N')).json"
    Write-WorkflowJson $recordPath $evidence
    $data['verification'] = @{files=$fileHashes; taskScopeHash=$evidence.taskScopeHash; record=[IO.Path]::GetRelativePath($root,$recordPath).Replace('\','/'); verdict=$evidence.verdict}
    Set-WorkflowTaskTransition $task $data $evidence.verdict "Independent verification: $($data.verification.record)" $latest.runId $latest.attemptId
    $metaPath = Join-Path $runs "$($latest.runId)/metadata.json"
    $metadata = Get-Content -LiteralPath $metaPath -Raw | ConvertFrom-Json -AsHashtable
    $metadata['verification'] = $evidence.verdict
    $metadata['verificationRecord'] = $data.verification.record
    $metadata['testedFingerprint'] = $evidence.testedFingerprint
    Write-WorkflowJson $metaPath $metadata
    Sync-WorkflowProgress $root
    $evidence | ConvertTo-Json -Depth 20
} finally { $handle.Dispose() }
