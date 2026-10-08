#requires -Version 7.2
# Adapter contract: invocation saves stdout/stderr and returns exitCode;
# normalization returns status, conversationId, deniedActions, and response.
function Invoke-WorkflowExecutor {
    param([string]$CliPath, [string[]]$Arguments, [string]$ProjectRoot, [string]$RunDirectory, [int]$TimeoutSeconds, [scriptblock]$OnStarted, [switch]$Stream, [scriptblock]$OnEvent)
    $stdoutPath = Join-Path $RunDirectory 'stdout.json'
    $stderrPath = Join-Path $RunDirectory 'stderr.log'
    # PowerShell-script adapters are retained for the existing credential-free mocks.
    if ([IO.Path]::GetExtension($CliPath) -eq '.ps1') {
        if ($Stream) { throw 'Live streaming requires a native CLI executable; .ps1 fixtures support JSON mode only.' }
        Push-Location -LiteralPath $ProjectRoot
        try {
            $global:LASTEXITCODE = 0
            & $CliPath @Arguments 1> $stdoutPath 2> $stderrPath
            return @{exitCode=$LASTEXITCODE}
        } finally { Pop-Location }
    }
    $info = [Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $CliPath
    $info.WorkingDirectory = $ProjectRoot
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $info
    if ($Stream) { return Invoke-WorkflowStreamingProcess -Process $process -RunDirectory $RunDirectory -TimeoutSeconds $TimeoutSeconds -OnStarted $OnStarted -OnEvent $OnEvent }
    $stdout = $null; $stderr = $null
    try {
        if (-not $process.Start()) { throw 'Executor process did not start.' }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if ($OnStarted) { & $OnStarted $process.Id $process.StartTime.ToUniversalTime().ToString('o') }
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill($true)
            if (-not $process.WaitForExit(5000)) { throw 'Executor could not be stopped; inspect processes before recovery.' }
            throw [TimeoutException]::new('Executor exceeded runner timeout; inspect partial changes before retrying.')
        }
        return @{exitCode=$process.ExitCode}
    } finally {
        if ($stdout -and -not $process.HasExited) { $process.Kill($true); $process.WaitForExit(5000) | Out-Null }
        foreach ($capturedStream in @(@{task=$stdout; path=$stdoutPath}, @{task=$stderr; path=$stderrPath})) {
            if ($capturedStream.task -and $capturedStream.task.Wait(5000)) { [IO.File]::WriteAllText($capturedStream.path, $capturedStream.task.Result) }
        }
        $process.Dispose()
    }
}
function Invoke-WorkflowStreamingProcess {
    param([Diagnostics.Process]$Process, [string]$RunDirectory, [int]$TimeoutSeconds, [scriptblock]$OnStarted, [scriptblock]$OnEvent)
    $events = [IO.StreamWriter]::new((Join-Path $RunDirectory 'events.ndjson'), $false, [Text.UTF8Encoding]::new($false))
    $diagnostics = [IO.StreamWriter]::new((Join-Path $RunDirectory 'stderr.log'), $false, [Text.UTF8Encoding]::new($false))
    $events.AutoFlush = $true; $diagnostics.AutoFlush = $true
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $started = $false; $invalid = $false; $final = $null; $conversationId = $null; $resultCount = 0
    try {
        if (-not $Process.Start()) { throw 'Executor process did not start.' }
        $started = $true
        if ($OnStarted) { & $OnStarted $Process.Id $Process.StartTime.ToUniversalTime().ToString('o') }
        $reads = @{
            output=@{reader=$Process.StandardOutput; pending=$Process.StandardOutput.ReadLineAsync(); closed=$false}
            error=@{reader=$Process.StandardError; pending=$Process.StandardError.ReadLineAsync(); closed=$false}
        }
        while (-not $reads.output.closed -or -not $reads.error.closed) {
            if ($clock.Elapsed.TotalSeconds -ge $TimeoutSeconds) { throw [TimeoutException]::new('Executor exceeded runner timeout; inspect partial changes before retrying.') }
            foreach ($name in @('output','error')) {
                $entry = $reads[$name]
                if ($entry.closed -or -not $entry.pending.IsCompleted) { continue }
                $line = $entry.pending.GetAwaiter().GetResult()
                if ($null -eq $line) { $entry.closed=$true; continue }
                if ($name -eq 'error') { $diagnostics.WriteLine($line) }
                else {
                    $events.WriteLine($line)
                    try {
                        $event = $line | ConvertFrom-Json -AsHashtable -ErrorAction Stop
                        if ($event -isnot [Collections.IDictionary] -or $event.event -notin @('init','step_update','result')) { throw 'Invalid stream event.' }
                        if ($event.event -eq 'init') { $conversationId = $event.conversation_id }
                        if ($event.event -eq 'result') { $final = $event.result; $resultCount++ }
                        if ($OnEvent) { & $OnEvent $event }
                    } catch { $invalid=$true; $diagnostics.WriteLine("Invalid streaming event: $($_.Exception.Message)") }
                }
                $entry.pending = $entry.reader.ReadLineAsync()
            }
            Start-Sleep -Milliseconds 10
        }
        $remaining = [Math]::Max(1, [int](($TimeoutSeconds - $clock.Elapsed.TotalSeconds) * 1000))
        if (-not $Process.WaitForExit($remaining)) { throw [TimeoutException]::new('Executor exceeded runner timeout; inspect partial changes before retrying.') }
        if ($invalid -or $resultCount -ne 1 -or $final -isnot [Collections.IDictionary]) { throw 'Invalid streaming output: expected exactly one final result and valid events.' }
        [IO.File]::WriteAllText((Join-Path $RunDirectory 'stdout.json'), ($final | ConvertTo-Json -Depth 30), [Text.UTF8Encoding]::new($false))
        return @{exitCode=$Process.ExitCode; conversationId=$conversationId}
    } finally {
        if ($started -and -not $Process.HasExited) { $Process.Kill($true); $Process.WaitForExit(5000) | Out-Null }
        $events.Dispose(); $diagnostics.Dispose(); $Process.Dispose()
    }
}
function Read-WorkflowExecutorResult {
    param([string]$Path, [int]$ExitCode)
    try {
        $result = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
        if ($result -isnot [Collections.IDictionary] -or $result.status -isnot [string] -or [string]::IsNullOrWhiteSpace($result.status)) { throw 'Missing executor status.' }
        if ($result.ContainsKey('response') -and $result.response -isnot [string]) { throw 'Invalid executor response.' }
        if ($result.ContainsKey('denied_actions') -and $null -ne $result.denied_actions -and $result.denied_actions -isnot [array]) { throw 'Invalid denied_actions.' }
        $status = $result.status
        if (@($result.denied_actions).Count -and $null -ne $result.denied_actions) { $status = 'blocked-permissions' }
        elseif ($status -eq 'SUCCESS' -and [string]::IsNullOrWhiteSpace($result.response)) { $status = 'empty-response' }
        elseif ($ExitCode -ne 0) { $status = 'failed' }
        return @{status=$status; executorStatus=$result.status; conversationId=$result.conversation_id; deniedActions=$result.denied_actions; response=$result.response}
    } catch { return @{status='invalid-output'; error=$_.Exception.Message} }
}
