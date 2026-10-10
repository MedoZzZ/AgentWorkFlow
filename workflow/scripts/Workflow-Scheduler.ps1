#requires -Version 7.2
function Get-WorkflowTaskIndex {
    param([string]$Root, $Plan)
    $index = @{}
    foreach ($file in Get-ChildItem -LiteralPath (Join-Path $Root 'workflow/tasks') -Filter '*.md' -File -Recurse) {
        $task = Read-WorkflowTask $file.FullName -AllowLegacy
        if (-not $task) { continue }
        if ($index.ContainsKey($task.taskId)) { throw "Duplicate Task ID: $($task.taskId)" }
        $index[$task.taskId] = @{data=$task; path=$file.FullName; approved=$false}
    }
    foreach ($entry in $Plan.tasks) {
        $path = Resolve-WorkflowLocalPath $Root $entry.file
        if (-not $index.ContainsKey($entry.taskId) -or -not [string]::Equals($index[$entry.taskId].path,$path,(Get-WorkflowPathComparison))) { throw "Approved task missing or path differs: $($entry.taskId)" }
        $item = $index[$entry.taskId]
        if ($entry.scopeHash -ne (Get-WorkflowTaskScopeHash $path) -or (ConvertTo-Json -Compress -InputObject @($entry.dependencies)) -cne (ConvertTo-Json -Compress -InputObject @($item.data.dependencies))) { throw "Approved scope/dependencies changed: $($entry.taskId)" }
        $item.approved = $true; $item['plan'] = $entry
    }
    # Validate the entire managed graph, including verified dependencies outside approved dispatch scope.
    $colors = @{}
    function Visit-WorkflowNode([string]$Id) {
        if ($colors[$Id] -eq 1) { throw "Cyclic dependency at $Id" }
        if ($colors[$Id] -eq 2) { return }
        $colors[$Id] = 1
        foreach ($dependency in $index[$Id].data.dependencies) {
            if (-not $index.ContainsKey($dependency)) { throw "Missing dependency $dependency for $Id" }
            Visit-WorkflowNode $dependency
        }
        $colors[$Id] = 2
    }
    foreach ($id in $index.Keys) { Visit-WorkflowNode $id }
    return $index
}
function Get-WorkflowNextAction {
    param([string]$Root, $Plan, $Index)
    function Test-CurrentApprovedReview($Item) {
        if (-not (Test-WorkflowVerificationCurrent $Root $Item.path $Item.data)) { return $false }
        if ($Plan.governance.requireReviewerIdentity -and (-not $Item.data.verification.revisionBound -or [string]::IsNullOrWhiteSpace($Item.data.verification.reviewer.id) -or [string]::IsNullOrWhiteSpace($Item.data.verification.reviewer.contextId))) { return $false }
        return $true
    }
    $completed=@(); $pending=@(); $blocked=@(); $candidates=@()
    foreach ($entry in $Plan.tasks) {
        $item = $Index[$entry.taskId]; $task = $item.data
        if (Test-CurrentApprovedReview $item) { $completed += $task.taskId; continue }
        $pending += $task.taskId
        if ($task.status -in @('blocked','in-progress')) { $blocked += $task.taskId }
        $dependenciesCurrent = $true
        foreach ($id in $task.dependencies) {
            if (-not (Test-CurrentApprovedReview $Index[$id])) { $dependenciesCurrent = $false }
        }
        if (-not $dependenciesCurrent -and $task.taskId -notin $blocked) { $blocked += $task.taskId }
        if ($dependenciesCurrent -and $task.status -notin @('blocked','in-progress')) { $candidates += $item }
    }
    # Stable ordinal tie-break, independent of culture and filesystem enumeration order.
    $chosen = $null
    foreach ($item in $candidates) {
        if (-not $chosen -or $item.plan.priority -gt $chosen.plan.priority -or ($item.plan.priority -eq $chosen.plan.priority -and [StringComparer]::Ordinal.Compare($item.data.taskId,$chosen.data.taskId) -lt 0)) { $chosen = $item }
    }
    $kind = if (-not $pending.Count) { 'final-review' } elseif (-not $chosen) { 'blocked' } elseif ($chosen.data.status -eq 'ready-for-verification') { 'task-review' } elseif ($chosen.data.status -in @('verified','failed','interrupted','needs-fix')) { 'repair' } else { 'dispatch' }
    return @{kind=$kind; task=$chosen; completed=$completed; pending=$pending; blocked=$blocked}
}
