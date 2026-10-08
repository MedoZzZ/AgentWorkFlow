#requires -Version 7.2
# Task Markdown owns state. JSON in a leading comment avoids a second state store.
$script:TaskHeaderPattern = '\A<!-- workflow-task\r?\n([\s\S]*?)\r?\n-->\r?\n'
$script:TaskTransitions = @{
    draft=@('ready','blocked'); ready=@('in-progress','blocked')
    'in-progress'=@('ready-for-verification','failed','interrupted','blocked')
    'ready-for-verification'=@('verified','needs-fix','blocked')
    'needs-fix'=@('in-progress','blocked'); failed=@('ready','blocked')
    interrupted=@('ready','blocked'); blocked=@('draft','ready','needs-fix'); verified=@('needs-fix')
}
function Read-WorkflowTask {
    param([string]$Path, [switch]$AllowLegacy)
    $content = [IO.File]::ReadAllText($Path)
    $match = [regex]::Match($content, $script:TaskHeaderPattern)
    if (-not $match.Success) {
        if ($AllowLegacy -and -not $content.Contains('workflow-task')) { return $null }
        throw "Missing or malformed workflow-task header: $Path"
    }
    $data = $match.Groups[1].Value | ConvertFrom-Json -AsHashtable
    if ($data.schemaVersion -ne 1 -or $data.taskId -isnot [string] -or $data.taskId -notmatch '^TASK-[A-Za-z0-9_-]+$') { throw 'Invalid task schema or Task ID.' }
    if (-not $script:TaskTransitions.ContainsKey([string]$data.status)) { throw 'Invalid task status.' }
    if ($data.dependencies -isnot [array] -or $data.history -isnot [array] -or $data.attempts -isnot [array]) { throw 'Task dependencies, history, and attempts must be arrays.' }
    if ($data.approval -isnot [string]) { throw 'Task approval must be a recorded instruction/reference string.' }
    foreach ($id in $data.dependencies) {
        if ($id -isnot [string] -or $id -notmatch '^TASK-[A-Za-z0-9_-]+$' -or $id -eq $data.taskId) { throw 'Invalid or self-referencing dependency.' }
    }
    return $data
}
function Assert-WorkflowTaskReady {
    param([string]$ProjectRoot, [string]$TaskPath, $Data)
    if ([string]::IsNullOrWhiteSpace($Data.approval)) { throw 'Implementation requires a recorded user approval reference.' }
    $index = @{}
    $taskPaths = @{}
    $paths = @($TaskPath)
    $directory = Join-Path $ProjectRoot 'workflow/tasks'
    if (Test-Path -LiteralPath $directory) { $paths += @(Get-ChildItem -LiteralPath $directory -Filter '*.md' -Recurse -File | ForEach-Object FullName) }
    foreach ($path in ($paths | Select-Object -Unique)) {
        $entry = Read-WorkflowTask -Path $path -AllowLegacy
        if ($null -eq $entry) { continue }
        if ($index.ContainsKey($entry.taskId)) { throw "Duplicate Task ID: $($entry.taskId)" }
        $index[$entry.taskId] = $entry
        $taskPaths[$entry.taskId] = $path
    }
    foreach ($id in $Data.dependencies) {
        if (-not $index.ContainsKey($id) -or $index[$id].status -ne 'verified') { throw "Dependency is not verified: $id" }
        $dependency = $index[$id]
        if (-not $dependency.verification -or $dependency.verification.verdict -ne 'verified') { throw "Dependency has no structured verification: $id" }
        if ($dependency.verification.taskScopeHash -ne (Get-WorkflowTaskScopeHash $taskPaths[$id])) { throw "Dependency task scope is stale: $id" }
        foreach ($relative in $dependency.verification.files.Keys) {
            $file = Join-Path $ProjectRoot $relative
            $hash = if (Test-Path -LiteralPath $file -PathType Leaf) { (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash } else { $null }
            if ($hash -ne $dependency.verification.files[$relative]) { throw "Dependency verification is stale: $id ($relative)" }
        }
    }
}
function Write-WorkflowTask {
    param([string]$Path, $Data)
    $content = [IO.File]::ReadAllText($Path)
    $match = [regex]::Match($content, $script:TaskHeaderPattern)
    if (-not $match.Success) { throw 'Task header disappeared during execution; reconcile before retrying.' }
    $body = $content.Substring($match.Length)
    $body = [regex]::Replace($body, '(?m)^Status: .+$', "Status: $($Data.status)")
    $output = "<!-- workflow-task`n$($Data | ConvertTo-Json -Depth 20)`n-->`n$body"
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary, $output, [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporary, $Path, $true)
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary } }
}
function Set-WorkflowTaskTransition {
    param([string]$Path, $Data, [string]$Status, [string]$Reason, [string]$RunId, [string]$AttemptId)
    if ([string]::IsNullOrWhiteSpace($Reason)) { throw 'A transition reason/evidence reference is required.' }
    if ($Status -notin $script:TaskTransitions[$Data.status]) { throw "Invalid task transition: $($Data.status) -> $Status" }
    $Data.history += @{from=$Data.status; to=$Status; reason=$Reason; runId=$RunId; attemptId=$AttemptId; timestampUtc=[DateTime]::UtcNow.ToString('o')}
    $Data.status = $Status
    Write-WorkflowTask -Path $Path -Data $Data
}
