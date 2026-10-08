#requires -Version 7.2
# Adapter contract: invocation saves stdout/stderr and returns exitCode;
# normalization returns status, conversationId, deniedActions, and response.
function Invoke-WorkflowExecutor {
    param([string]$CliPath, [string[]]$Arguments, [string]$ProjectRoot, [string]$RunDirectory, [int]$TimeoutSeconds, [scriptblock]$OnStarted)
    $stdoutPath = Join-Path $RunDirectory 'stdout.json'
    $stderrPath = Join-Path $RunDirectory 'stderr.log'
    # PowerShell-script adapters are retained for the existing credential-free mocks.
    if ([IO.Path]::GetExtension($CliPath) -eq '.ps1') {
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
        foreach ($stream in @(@{task=$stdout; path=$stdoutPath}, @{task=$stderr; path=$stderrPath})) {
            if ($stream.task -and $stream.task.Wait(5000)) { [IO.File]::WriteAllText($stream.path, $stream.task.Result) }
        }
        $process.Dispose()
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
