param([Parameter(Mandatory)][string]$ProjectRoot)
$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$cli = Get-Command agy -ErrorAction SilentlyContinue
$cliPath = if ($cli) { $cli.Source } else { Join-Path $env:LOCALAPPDATA 'agy\bin\agy.exe' }
$git = Get-Command git -ErrorAction SilentlyContinue
$head = $null; $changes = @(); $gitAvailable = $false
if ($git) {
    $headOutput = & git -C $root rev-parse HEAD 2>$null
    if ($LASTEXITCODE -eq 0) {
        $head = "$headOutput"; $gitAvailable = $true
        $changes = @(& git -C $root status --porcelain)
    }
}
$runtimes = [ordered]@{}
foreach ($name in @('node','npm','pnpm','python','dotnet','go')) {
    $command = Get-Command $name -ErrorAction SilentlyContinue
    $runtimes[$name] = if ($command) { $command.Source } else { $null }
}
$files = @('package.json','package-lock.json','pnpm-lock.yaml','yarn.lock','pyproject.toml','requirements.txt','go.mod','Cargo.toml')
[ordered]@{
    projectRoot = $root
    cliPath = $cliPath
    cliAvailable = (Test-Path -LiteralPath $cliPath -PathType Leaf)
    gitRepository = $gitAvailable
    baselineRevision = $head
    existingChanges = $changes
    runtimeCommands = $runtimes
    manifests = @($files | Where-Object { Test-Path -LiteralPath (Join-Path $root $_) })
    workflowPresent = (Test-Path -LiteralPath (Join-Path $root 'workflow\LIFECYCLE.md'))
    baselineChecks = 'Not run: select the actual project commands in CI.md before implementation.'
} | ConvertTo-Json -Depth 5
