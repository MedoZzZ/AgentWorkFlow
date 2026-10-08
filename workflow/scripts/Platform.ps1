#requires -Version 7.2
# Shared discovery and path rules for PowerShell on Windows and Linux.
function Get-WorkflowPathComparison {
    if ($IsWindows) { return [StringComparison]::OrdinalIgnoreCase }
    return [StringComparison]::Ordinal
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
