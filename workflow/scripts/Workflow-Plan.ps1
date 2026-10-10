#requires -Version 7.2
# Shared by the controller and check runner. Paths are workspace relative and never follow links.
. (Join-Path $PSScriptRoot 'Governance.ps1')
function Resolve-WorkflowLocalPath {
    param([string]$Root, [string]$Relative, [switch]$Directory)
    if ([string]::IsNullOrWhiteSpace($Relative) -or [IO.Path]::IsPathRooted($Relative) -or $Relative.Contains('\') -or @($Relative.Split('/') | Where-Object { $_ -in @('..','.','') }).Count) { throw "Invalid workspace path: $Relative" }
    $current = $Root
    foreach ($part in $Relative.Split('/')) {
        $current = Join-Path $current $part
        if (Test-Path -LiteralPath $current) {
            if ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Workflow cannot follow symbolic links: $Relative" }
        }
    }
    if ($Directory -and -not (Test-Path -LiteralPath $current -PathType Container)) { throw "Missing working directory: $Relative" }
    return $current
}
function Assert-WorkflowInteger {
    param($Value, [int]$Minimum, [int]$Maximum, [string]$Name)
    if (($Value -isnot [int] -and $Value -isnot [long]) -or $Value -lt $Minimum -or $Value -gt $Maximum) { throw "Invalid $Name; expected integer $Minimum..$Maximum." }
}
function Read-WorkflowPlan {
    param([string]$Root, [string]$Path)
    $plan = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
    if ($plan.schemaVersion -ne 1 -or $plan.workflowId -notmatch '^[A-Za-z0-9_-]+$' -or [string]::IsNullOrWhiteSpace($plan.approvalReference)) { throw 'Plan requires schemaVersion 1, workflowId and explicit approvalReference.' }
    if ($plan.tasks -isnot [array] -or -not $plan.tasks.Count) { throw 'Plan requires an explicit nonempty task scope.' }
    Assert-WorkflowInteger $plan.limits.maxRepairAttempts 0 20 'maxRepairAttempts'
    Assert-WorkflowInteger $plan.limits.taskTimeoutSeconds 10 3600 'taskTimeoutSeconds'
    Assert-WorkflowInteger $plan.limits.workflowTimeoutSeconds 10 604800 'workflowTimeoutSeconds'
    if ($plan.coordinatorMode -cne 'active-session' -or $plan.allowDeployment -isnot [bool] -or $plan.allowDeployment) { throw 'Only active-session coordination without deployment is supported.' }
    if ($plan.governance -and $plan.governance.requireReviewerIdentity -isnot [bool]) { throw 'governance.requireReviewerIdentity must be a boolean.' }
    $ids = @{}
    foreach ($entry in $plan.tasks) {
        if ($entry.taskId -notmatch '^TASK-[A-Za-z0-9_-]+$' -or $ids.ContainsKey($entry.taskId)) { throw 'Invalid or duplicate approved Task ID.' }
        $ids[$entry.taskId] = $true
        if ($entry.scopeHash -notmatch '^[A-Fa-f0-9]{64}$' -or $entry.dependencies -isnot [array]) { throw "Missing task scope hash/dependencies: $($entry.taskId)" }
        Assert-WorkflowInteger $entry.priority -100000 100000 'priority'
        $null = Resolve-WorkflowLocalPath $Root $entry.file
        if ($entry.allowedFiles -isnot [array] -or -not $entry.allowedFiles.Count) { throw 'Each task requires exact allowedFiles (no wildcards).' }
        foreach ($file in $entry.allowedFiles) {
            $null = Resolve-WorkflowLocalPath $Root $file
            if ($file -match '[*?]' -or $file -match '^workflow/(runs|tasks)(/|$)') { throw 'Allowed files cannot include state stores or wildcards.' }
        }
        if ($entry.checks -isnot [array] -or -not $entry.checks.Count -or $entry.acceptanceCriteria -isnot [array] -or -not $entry.acceptanceCriteria.Count) { throw 'Each task requires checks and acceptance criteria.' }
        $names = @{}
        foreach ($check in $entry.checks) {
            if ([string]::IsNullOrWhiteSpace($check.name) -or $names.ContainsKey($check.name) -or [string]::IsNullOrWhiteSpace($check.executable) -or $check.arguments -isnot [array] -or $check.required -isnot [bool] -or $check.platform -notin @('all','windows','linux')) { throw 'Invalid approved check.' }
            $names[$check.name] = $true
            foreach ($argument in $check.arguments) { if ($argument -isnot [string]) { throw 'Check arguments must be strings.' } }
            Assert-WorkflowInteger $check.timeoutSeconds 1 3600 'check timeoutSeconds'
            if ($check.workingDirectory -ne '') { $null = Resolve-WorkflowLocalPath $Root $check.workingDirectory -Directory }
        }
        $names = @{}
        foreach ($criterion in $entry.acceptanceCriteria) {
            if ([string]::IsNullOrWhiteSpace($criterion.name) -or $names.ContainsKey($criterion.name) -or $criterion.required -isnot [bool]) { throw 'Invalid approved acceptance criterion.' }
            $names[$criterion.name] = $true
        }
        Assert-WorkflowGovernanceRecords $Root $entry
    }
    return $plan
}
function Test-WorkflowVerificationCurrent {
    param([string]$Root, [string]$TaskPath, $Task)
    if ($Task.status -ne 'verified' -or $Task.verification.verdict -ne 'verified' -or -not $Task.verification.files -or $Task.verification.taskScopeHash -ne (Get-WorkflowTaskScopeHash $TaskPath)) { return $false }
    if ($Task.verification.revisionBound -and $Task.verification.testedRevision -cne (Get-WorkflowRevision $Root)) { return $false }
    if ($Task.verification.revisionBound -and (ConvertTo-Json -Compress -InputObject @($Task.verification.dependencies)) -cne (ConvertTo-Json -Compress -InputObject @($Task.dependencies))) { return $false }
    foreach ($file in $Task.verification.files.Keys) {
        $path = Resolve-WorkflowLocalPath $Root $file
        $actual = if (Test-Path -LiteralPath $path -PathType Leaf) { (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash } else { $null }
        if ($actual -ne $Task.verification.files[$file]) { return $false }
    }
    return $true
}
