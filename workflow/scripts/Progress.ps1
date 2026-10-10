#requires -Version 7.2
# Caller holds the project lock. Replace only the generated section.
function Sync-WorkflowProgress {
    param([string]$ProjectRoot)
    $directory = Join-Path $ProjectRoot 'workflow/tasks'
    $rows = @()
    if (Test-Path -LiteralPath $directory) {
        foreach ($file in (Get-ChildItem -LiteralPath $directory -Filter '*.md' -Recurse -File | Sort-Object FullName)) {
            $task = Read-WorkflowTask -Path $file.FullName -AllowLegacy
            if (-not $task) { continue }
            $run = if ($task.attempts.Count) { $task.attempts[-1].runId } else { 'none' }
            $rows += "| $($task.taskId) | $($task.status) | $($task.dependencies -join ', ') | $($task.attempts.Count) | $run |"
        }
    }
    $section = "<!-- workflow-progress:start -->`n## Managed task summary (generated)`n`nUpdated UTC: $([DateTime]::UtcNow.ToString('o'))`n`n| Task | State | Dependencies | Attempts | Latest run |`n| --- | --- | --- | --- | --- |`n$($rows -join "`n")`n`nState reflects task records. Independent verification may become stale after file edits; dispatch checks dependency evidence. User acceptance and release remain separate.`n<!-- workflow-progress:end -->"
    $workflows = Join-Path $ProjectRoot 'workflow/runs/_workflows'
    if (Test-Path -LiteralPath $workflows) {
        $workflowRows = @()
        foreach ($file in Get-ChildItem -LiteralPath $workflows -Filter state.json -Recurse -File | Sort-Object FullName) {
            $state = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -AsHashtable
            $reason = ([string]$state.stopReason).Replace('|','/').Replace("`n",' ').Replace("`r",' ')
            $workflowRows += "| $($state.workflowId) | $($state.phase) | $($state.activeTask) | $($state.pending.Count) | $reason |"
        }
        $workflowSection = "`n`n## Workflow checkpoints (generated)`n`n| Workflow | Phase | Active task | Pending at checkpoint | Stop reason |`n| --- | --- | --- | --- | --- |`n$($workflowRows -join "`n")`n`nCheckpoints record the last controller action. Active reasoning requires a coordinator session.`n"
        $section = $section.Replace('<!-- workflow-progress:end -->', $workflowSection + '<!-- workflow-progress:end -->')
    }
    $path = Join-Path $ProjectRoot 'workflow/PROGRESS.md'
    $content = if (Test-Path -LiteralPath $path) { [IO.File]::ReadAllText($path) } else { "# Progress`n" }
    $pattern = '(?s)<!-- workflow-progress:start -->.*?<!-- workflow-progress:end -->'
    if ([regex]::IsMatch($content, $pattern)) { $content = [regex]::Replace($content, $pattern, [Text.RegularExpressions.MatchEvaluator]{ param($match) $section }) }
    else { $content = $content.TrimEnd() + "`n`n$section`n" }
    $temporary = "$path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary, $content, [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporary, $path, $true)
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary } }
}
