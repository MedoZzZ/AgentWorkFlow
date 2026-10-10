#requires -Version 7.2
function Write-WorkflowJson {
    param([string]$Path, $Value)
    $temporary = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporary, $Path, $true)
    } finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary } }
}
function Get-WorkflowSnapshot {
    param([string]$ProjectRoot)
    $root = [IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\','/')
    $files = [Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
    $pending = [Collections.Generic.Stack[string]]::new()
    $pending.Push($root)
    while ($pending.Count) {
        $directory = $pending.Pop()
        foreach ($entry in [IO.Directory]::EnumerateFileSystemEntries($directory)) {
            $relative = [IO.Path]::GetRelativePath($root, $entry).Replace('\','/')
            $attributes = [IO.File]::GetAttributes($entry)
            if ($attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Snapshot cannot follow symbolic links/reparse points: $relative" }
            if ($attributes -band [IO.FileAttributes]::Directory) {
                if ((Split-Path $entry -Leaf) -in @('.git','node_modules','.pilot') -or $relative -in @('workflow/runs','workflow/tasks')) { continue }
                $pending.Push($entry)
            } elseif ($relative -notin @('workflow/PROGRESS.md','workflow/projects.json')) {
                $files[$relative] = (Get-FileHash -LiteralPath $entry -Algorithm SHA256).Hash
            }
        }
    }
    $sorted = [Collections.Specialized.OrderedDictionary]::new([StringComparer]::Ordinal)
    foreach ($key in ($files.Keys | Sort-Object -CaseSensitive)) { $sorted[$key] = $files[$key] }
    $serialized = $sorted | ConvertTo-Json -Compress -Depth 5
    $fingerprint = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($serialized)))
    $revision = $null
    if (Get-Command git -ErrorAction SilentlyContinue) {
        $savedNativeExit = $global:LASTEXITCODE
        try {
            $head = & git -C $root rev-parse HEAD 2>$null
            if ($LASTEXITCODE -eq 0) { $revision = "$head" }
        } catch { $revision = $null }
        finally { $global:LASTEXITCODE = $savedNativeExit }
    }
    return @{schemaVersion=1; timestampUtc=[DateTime]::UtcNow.ToString('o'); revision=$revision; fingerprint=$fingerprint; files=$sorted; exclusions=@('.git','node_modules','.pilot','workflow/runs','workflow/tasks','workflow/PROGRESS.md','workflow/projects.json')}
}
function Compare-WorkflowSnapshot {
    param($Before, $After)
    $changes = @()
    foreach ($path in (@($Before.files.Keys) + @($After.files.Keys) | Sort-Object -Unique -CaseSensitive)) {
        if (-not $Before.files.Contains($path)) { $kind = 'added' }
        elseif (-not $After.files.Contains($path)) { $kind = 'deleted' }
        elseif ($Before.files[$path] -ne $After.files[$path]) { $kind = 'modified' }
        else { continue }
        $changes += @{path=$path; kind=$kind; before=$Before.files[$path]; after=$After.files[$path]}
    }
    return ,$changes
}
function Get-WorkflowTaskScopeHash {
    param([string]$TaskFile)
    $content = [IO.File]::ReadAllText($TaskFile)
    $content = [regex]::Replace($content, $script:TaskHeaderPattern, '')
    $content = [regex]::Replace($content, '(?m)^Status: .*\r?\n', '')
    $content = ($content -split '(?m)^## Executor result', 2)[0]
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($content)))
}
