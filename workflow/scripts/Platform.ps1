#requires -Version 7.2
# Shared discovery and path rules for PowerShell on Windows and Linux.
function Get-WorkflowPathComparison {
    if ($IsWindows) { return [StringComparison]::OrdinalIgnoreCase }
    return [StringComparison]::Ordinal
}

function Test-WorkflowExecutable {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    if (-not $IsLinux) { return $true }
    $test = Get-Command test -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $test) { return $false }
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $test.Source; $info.UseShellExecute = $false
    $info.ArgumentList.Add('-x'); $info.ArgumentList.Add($Path)
    $process = [Diagnostics.Process]::Start($info)
    try { $process.WaitForExit(); return $process.ExitCode -eq 0 } finally { $process.Dispose() }
}

function Resolve-WorkflowCli {
    param([string]$ConfiguredPath)
    if ($ConfiguredPath) { return $ConfiguredPath }
    $command = Get-Command agy -CommandType Application -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    if ($IsWindows) {
        $localData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
        return Join-Path $localData 'agy/bin/agy.exe'
    }
    $userProfile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
    return Join-Path $userProfile '.local/bin/agy'
}
