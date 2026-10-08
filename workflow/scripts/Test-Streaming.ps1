#requires -Version 7.2
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Platform.ps1')
. (Join-Path $PSScriptRoot 'Antigravity-Adapter.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('agentworkflow-stream-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$job = $null
try {
    $emitter = Join-Path $fixture 'emit.ps1'
    @'
[Console]::Out.WriteLine('{"event":"init","conversation_id":"stream-fixture"}')
[Console]::Error.WriteLine('diagnostic before completion')
Start-Sleep -Milliseconds 1200
[Console]::Out.WriteLine('{"event":"step_update","step_update":{"step_index":1,"step_type":"agent_response","state":"ACTIVE","text_delta":"Hello "}}')
[Console]::Out.WriteLine('{"event":"step_update","step_update":{"step_index":1,"step_type":"agent_response","state":"DONE","text_delta":"world"}}')
[Console]::Out.WriteLine('{"event":"result","result":{"status":"SUCCESS","response":"Hello world","conversation_id":"stream-fixture"}}')
'@ | Set-Content -LiteralPath $emitter
    $pwshPath = (Get-Process -Id $PID).Path
    $job = Start-Job -ScriptBlock {
        param($adapter,$cli,$scriptFile,$directory)
        . $adapter
        Invoke-WorkflowExecutor -CliPath $cli -Arguments @('-NoProfile','-File',$scriptFile) -ProjectRoot $directory -RunDirectory $directory -TimeoutSeconds 10 -Stream
    } -ArgumentList (Join-Path $PSScriptRoot 'Antigravity-Adapter.ps1'),$pwshPath,$emitter,$fixture
    $timer=[Diagnostics.Stopwatch]::StartNew(); $sawLive=$false
    while ($timer.Elapsed.TotalSeconds -lt 8 -and $job.State -eq 'Running') {
        $eventPath=Join-Path $fixture 'events.ndjson'
        if ((Test-Path -LiteralPath $eventPath) -and (Get-Content -LiteralPath $eventPath -Raw) -like '*stream-fixture*' -and -not (Test-Path -LiteralPath (Join-Path $fixture 'stdout.json'))) { $sawLive=$true; break }
        Start-Sleep -Milliseconds 50
    }
    $result=$job | Receive-Job -Wait -ErrorAction Stop
    if (-not $sawLive -or $result.exitCode -ne 0 -or $result.conversationId -ne 'stream-fixture') { throw 'Events were not persisted while the executor was running.' }
    $final=Get-Content -LiteralPath (Join-Path $fixture 'stdout.json') -Raw | ConvertFrom-Json
    if ($final.response -ne 'Hello world' -or (Get-Content -LiteralPath (Join-Path $fixture 'events.ndjson')).Count -ne 4) { throw 'Streaming final result compatibility failed.' }
    if ((Get-Content -LiteralPath (Join-Path $fixture 'stderr.log') -Raw) -notlike '*diagnostic before completion*') { throw 'Streaming stderr was lost.' }
    'invalid-json' | Set-Content -LiteralPath $emitter
    $rejected=$false
    try { Invoke-WorkflowExecutor -CliPath $pwshPath -Arguments @('-NoProfile','-Command','[Console]::Out.WriteLine("not-json")') -ProjectRoot $fixture -RunDirectory $fixture -TimeoutSeconds 10 -Stream | Out-Null } catch { if ($_.Exception.Message -notlike 'Invalid streaming output*') { throw }; $rejected=$true }
    if (-not $rejected) { throw 'Malformed stream accepted.' }
    $timedOut=$false
    try { Invoke-WorkflowExecutor -CliPath $pwshPath -Arguments @('-NoProfile','-Command','[Console]::Out.WriteLine(''{"event":"init","conversation_id":"timeout"}''); Start-Sleep -Seconds 30') -ProjectRoot $fixture -RunDirectory $fixture -TimeoutSeconds 1 -Stream | Out-Null } catch { if ($_.Exception -isnot [TimeoutException]) { throw }; $timedOut=$true }
    if (-not $timedOut -or (Get-Content -LiteralPath (Join-Path $fixture 'events.ndjson') -Raw) -notlike '*timeout*') { throw 'Streaming timeout did not preserve partial events.' }
    'PASS: native live NDJSON persistence, text deltas, final JSON compatibility, diagnostics, malformed events, and streaming timeout.'
} finally {
    if ($job) { $job | Remove-Job -Force }
    $target=[IO.Path]::GetFullPath($fixture)
    $prefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if ($target.StartsWith($prefix,(Get-WorkflowPathComparison)) -and (Split-Path $target -Leaf) -like 'agentworkflow-stream-*') { Remove-Item -LiteralPath $target -Recurse -Force }
}
$global:LASTEXITCODE=0
