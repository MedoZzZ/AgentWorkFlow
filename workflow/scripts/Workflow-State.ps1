#requires -Version 7.2
function Save-WorkflowCheckpoint {
    param([string]$Path, $State, [string]$Phase, [string]$Reason = '')
    $State.phase = $Phase; $State.stopReason = $Reason; $State.updatedUtc = [DateTime]::UtcNow.ToString('o')
    $State.history += @{phase=$Phase; reason=$Reason; taskId=$State.activeTask; runId=$State.activeRun; timestampUtc=$State.updatedUtc}
    Write-WorkflowJson $Path $State
}
function Get-WorkflowRemainingSeconds {
    param($State, $Plan)
    return [Math]::Floor($Plan.limits.workflowTimeoutSeconds - ([DateTime]::UtcNow - ([DateTime]$State.startedUtc).ToUniversalTime()).TotalSeconds)
}
function Assert-WorkflowNoLiveProcess {
    param($Metadata)
    foreach ($pair in @(@('executorProcessId','executorStartedUtc'),@('processId','runnerStartedUtc'))) {
        if ($pair[0] -eq 'processId' -and $Metadata.status -ne 'running') { continue }
        if (-not $Metadata[$pair[0]]) { continue }
        $process = Get-Process -Id $Metadata[$pair[0]] -ErrorAction SilentlyContinue
        if (-not $process) { continue }
        if (-not $Metadata[$pair[1]] -or [Math]::Abs(($process.StartTime.ToUniversalTime() - ([DateTime]$Metadata[$pair[1]]).ToUniversalTime()).TotalSeconds) -lt 1) { throw 'Recorded execution process is still live; wait before recovery.' }
    }
}
