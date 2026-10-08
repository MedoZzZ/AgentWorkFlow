#requires -Version 7.2
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Platform.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('agentworkflow-config-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $fixture 'workflow') -Force | Out-Null
try {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../config.json') -Destination (Join-Path $fixture 'workflow/config.json')
    $expectedConfig = Get-Content -LiteralPath (Join-Path $fixture 'workflow/config.json') -Raw | ConvertFrom-Json
    'Read-only fixture task' | Set-Content -LiteralPath (Join-Path $fixture 'task.md')
    $mockCli = Join-Path $fixture 'mock-cli.ps1'
    '$global:LASTEXITCODE = 0; @{status="SUCCESS"; conversation_id="fixture"; response=($args -join "|")} | ConvertTo-Json -Compress' | Set-Content -LiteralPath $mockCli
    $runner = Join-Path $PSScriptRoot 'Run-Antigravity.ps1'
    $base = @{ProjectRoot=$fixture; TaskFile=(Join-Path $fixture 'task.md'); CliPath=$mockCli}
    & $runner @base -RunId defaults | Out-Null
    $metadata = Get-Content -LiteralPath (Join-Path $fixture 'workflow/runs/defaults/metadata.json') -Raw | ConvertFrom-Json
    if ($metadata.model -ne $expectedConfig.antigravity.model -or $metadata.mode -ne $expectedConfig.antigravity.mode -or $metadata.timeoutSeconds -ne $expectedConfig.antigravity.timeoutSeconds) { throw 'Default settings failed.' }
    $response = Get-Content -LiteralPath (Join-Path $fixture 'workflow/runs/defaults/stdout.json') -Raw | ConvertFrom-Json
    if (-not $response.response.Contains('--model|' + $expectedConfig.antigravity.model + '|')) { throw 'Model flag not passed to CLI.' }
    $duplicateRejected = $false
    try { & $runner @base -RunId defaults | Out-Null } catch {
        if ($_.Exception.Message -notlike 'Run ID already exists*') { throw }
        $duplicateRejected = $true
    }
    if (-not $duplicateRejected) { throw 'Duplicate run ID was accepted.' }
    & $runner @base -RunId overrides -Model gemini-3.8-flash-medium -TimeoutSeconds 30 -Mode accept-edits | Out-Null
    $metadata = Get-Content -LiteralPath (Join-Path $fixture 'workflow/runs/overrides/metadata.json') -Raw | ConvertFrom-Json
    if ($metadata.model -ne 'gemini-3.8-flash-medium' -or $metadata.mode -ne 'accept-edits' -or $metadata.timeoutSeconds -ne 30) { throw 'Argument precedence failed.' }
    foreach ($case in @(
        @{name='denied'; body='$global:LASTEXITCODE=0; ''{"status":"SUCCESS","response":"","denied_actions":[{"action":"command"}]}'''; expected='blocked-permissions'},
        @{name='empty'; body='$global:LASTEXITCODE=0; ''{"status":"SUCCESS","response":""}'''; expected='empty-response'},
        @{name='crash'; body='throw "simulated CLI crash"'; expected='failed'},
        @{name='nonzero'; body='$global:LASTEXITCODE=1; ''{"status":"SUCCESS","response":"misleading success"}'''; expected='failed'},
        @{name='malformed'; body='$global:LASTEXITCODE=0; ''not-json'''; expected='invalid-output'}
    )) {
        $case.body | Set-Content -LiteralPath $mockCli
        $failed = $false
        try { & $runner @base -RunId $case.name | Out-Null } catch { $failed=$true }
        $runMeta = Get-Content -LiteralPath (Join-Path $fixture "workflow/runs/$($case.name)/metadata.json") -Raw | ConvertFrom-Json
        if (-not $failed -or $runMeta.status -ne $case.expected) { throw "Failure classification failed: $($case.name)" }
    }
    $activeLock = [IO.File]::Open((Join-Path $fixture 'workflow/runs/active.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $rejected = $false
        try { & $runner @base -RunId concurrent | Out-Null } catch { if ($_.Exception.Message -notlike 'Another dispatch*') { throw }; $rejected=$true }
        if (-not $rejected -or (Test-Path -LiteralPath (Join-Path $fixture 'workflow/runs/concurrent'))) { throw 'Project concurrency guard failed.' }
        $lockJob = Start-Job -ScriptBlock {
            param($lockPath)
            try {
                $handle = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::Write, [IO.FileShare]::None)
                $handle.Dispose()
                'unexpected-access'
            } catch { 'locked' }
        } -ArgumentList (Join-Path $fixture 'workflow/runs/active.lock')
        try {
            $jobResult = $lockJob | Receive-Job -Wait
            if ($jobResult -ne 'locked') { throw 'Cross-process project lock failed.' }
        } finally { $lockJob | Remove-Job -Force }
    } finally { $activeLock.Dispose() }
    if (-not $IsWindows) {
        $caseRoot = Join-Path $fixture 'project'
        $otherRoot = Join-Path $fixture 'PROJECT'
        New-Item -ItemType Directory -Path $caseRoot, $otherRoot | Out-Null
        $otherTask = Join-Path $otherRoot 'task.md'
        'Outside the selected case-sensitive project' | Set-Content -LiteralPath $otherTask
        $rejected = $false
        try {
            & $runner -ProjectRoot $caseRoot -TaskFile $otherTask -RunId outside -ConfigPath (Join-Path $fixture 'workflow/config.json') -CliPath $mockCli | Out-Null
        } catch { if ($_.Exception.Message -notlike 'Task must be inside*') { throw }; $rejected=$true }
        if (-not $rejected -or (Test-Path -LiteralPath (Join-Path $caseRoot 'workflow/runs'))) { throw 'Case-sensitive project containment failed.' }
        if ((Resolve-WorkflowCli -ConfiguredPath '/custom/agy') -ne '/custom/agy') { throw 'Explicit Linux CLI path failed.' }
    }
    $configPath = Join-Path $fixture 'workflow/config.json'
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $config.antigravity.timeoutSeconds = 0
    $config | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $configPath
    $rejected = $false
    try { & $runner @base -RunId invalid | Out-Null } catch { if ($_.Exception.Message -notlike '*timeoutSeconds*') { throw }; $rejected = $true }
    if (-not $rejected -or (Test-Path -LiteralPath (Join-Path $fixture 'workflow/runs/invalid'))) { throw 'Invalid config was not rejected before dispatch.' }
    "PASS ($($PSVersionTable.Platform)): configurable defaults, model forwarding, overrides, denied/empty/crashed/malformed results, cross-process locking, platform path rules, and invalid configuration."
} finally {
    # Delete only the exact temporary fixture created by this test.
    $resolvedFixture = [IO.Path]::GetFullPath($fixture)
    $tempPrefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    if ($resolvedFixture.StartsWith($tempPrefix, (Get-WorkflowPathComparison)) -and (Split-Path $resolvedFixture -Leaf) -like 'agentworkflow-config-*') {
        Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
    }
}
