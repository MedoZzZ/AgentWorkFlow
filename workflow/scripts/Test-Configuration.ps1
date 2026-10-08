$ErrorActionPreference = 'Stop'
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('agentworkflow-config-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $fixture 'workflow') -Force | Out-Null
try {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\config.json') -Destination (Join-Path $fixture 'workflow\config.json')
    'Read-only fixture task' | Set-Content -LiteralPath (Join-Path $fixture 'task.md')
    $mockCli = Join-Path $fixture 'mock-cli.ps1'
    '$global:LASTEXITCODE = 0; @{status="SUCCESS"; conversation_id="fixture"; response=($args -join "|")} | ConvertTo-Json -Compress' | Set-Content -LiteralPath $mockCli
    $runner = Join-Path $PSScriptRoot 'Run-Antigravity.ps1'
    $base = @{ProjectRoot=$fixture; TaskFile=(Join-Path $fixture 'task.md'); CliPath=$mockCli}
    & $runner @base -RunId defaults | Out-Null
    $metadata = Get-Content -LiteralPath (Join-Path $fixture 'workflow\runs\defaults\metadata.json') -Raw | ConvertFrom-Json
    if ($metadata.model -ne 'gemini-3.8-flash-high' -or $metadata.mode -ne 'plan' -or $metadata.timeoutSeconds -ne 600) { throw 'Default settings failed.' }
    $response = Get-Content -LiteralPath (Join-Path $fixture 'workflow\runs\defaults\stdout.json') -Raw | ConvertFrom-Json
    if ($response.response -notlike '*--model|gemini-3.8-flash-high*') { throw 'Model flag not passed to CLI.' }
    & $runner @base -RunId overrides -Model gemini-3.8-flash-medium -TimeoutSeconds 30 -Mode accept-edits | Out-Null
    $metadata = Get-Content -LiteralPath (Join-Path $fixture 'workflow\runs\overrides\metadata.json') -Raw | ConvertFrom-Json
    if ($metadata.model -ne 'gemini-3.8-flash-medium' -or $metadata.mode -ne 'accept-edits' -or $metadata.timeoutSeconds -ne 30) { throw 'Argument precedence failed.' }
    $configPath = Join-Path $fixture 'workflow\config.json'
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $config.antigravity.timeoutSeconds = 0
    $config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $configPath
    $rejected = $false
    try { & $runner @base -RunId invalid | Out-Null } catch { if ($_.Exception.Message -notlike '*timeoutSeconds*') { throw }; $rejected = $true }
    if (-not $rejected -or (Test-Path -LiteralPath (Join-Path $fixture 'workflow\runs\invalid'))) { throw 'Invalid config was not rejected before dispatch.' }
    'PASS: defaults, model flag forwarding, argument overrides, and invalid-config rejection.'
} finally {
    # Delete only the exact temporary fixture created by this test.
    $resolvedFixture = [IO.Path]::GetFullPath($fixture)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    if ($resolvedFixture.StartsWith($tempPrefix, [StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolvedFixture -Leaf) -like 'agentworkflow-config-*') {
        Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
    }
}
