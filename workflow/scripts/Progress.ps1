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
