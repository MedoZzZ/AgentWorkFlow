#requires -Version 7.2
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Task-State.ps1')
. (Join-Path $PSScriptRoot 'Platform.ps1')
. (Join-Path $PSScriptRoot 'Evidence.ps1')
$fixture = Join-Path ([IO.Path]::GetTempPath()) ('agentworkflow-state-' + [guid]::NewGuid().ToString('N'))
function Assert-Rejected {
    param([scriptblock]$Action, [string]$Pattern)
    try { & $Action | Out-Null } catch { if ($_.Exception.Message -notlike $Pattern) { throw }; return }
    throw "Expected rejection: $Pattern"
}
try {
    New-Item -ItemType Directory -Path (Join-Path $fixture 'workflow/tasks') -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../config.json') -Destination (Join-Path $fixture 'workflow/config.json')
    $task = Join-Path $fixture 'workflow/tasks/TASK-001.md'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot '../TASK-TEMPLATE.md') -Destination $task
    $data = Read-WorkflowTask $task
    $data.taskId = 'TASK-001'
    Write-WorkflowTask $task $data
    $setter = Join-Path $PSScriptRoot 'Set-TaskStatus.ps1'
    Assert-Rejected { & $setter -ProjectRoot $fixture -TaskFile $task -Status ready -Reason approved } '*approval reference*'
    $data.approval = 'User approved fixture scope'
    $data.dependencies = @('TASK-002')
    Write-WorkflowTask $task $data
    Assert-Rejected { & $setter -ProjectRoot $fixture -TaskFile $task -Status ready -Reason approved } '*Dependency is not verified*'
    $dependency = Join-Path $fixture 'workflow/tasks/TASK-002.md'
    Copy-Item -LiteralPath $task -Destination $dependency
    Assert-Rejected { Assert-WorkflowTaskReady $fixture $task $data } '*Duplicate Task ID*'
    $dependencyData = Read-WorkflowTask $dependency
    $dependencyData.taskId = 'TASK-002'; $dependencyData.dependencies = @(); $dependencyData.status = 'verified'
    Write-WorkflowTask $dependency $dependencyData
    $dependencyData['verification'] = @{verdict='verified'; files=@{}; taskScopeHash=(Get-WorkflowTaskScopeHash $dependency)}
    Write-WorkflowTask $dependency $dependencyData
    & $setter -ProjectRoot $fixture -TaskFile $task -Status ready -Reason approved | Out-Null
    Assert-Rejected { & $setter -ProjectRoot $fixture -TaskFile $task -Status verified -Reason invalid } '*Use Record-Verification*'
    Assert-Rejected { & $setter -ProjectRoot $fixture -TaskFile $task -Status needs-fix -Reason invalid } '*Invalid task transition*'
    $mock = Join-Path $fixture 'mock.ps1'
    '$global:LASTEXITCODE=0; ''{"status":"SUCCESS","response":"done"}''' | Set-Content -LiteralPath $mock
    $runner = Join-Path $PSScriptRoot 'Run-Antigravity.ps1'
    $base = @{ProjectRoot=$fixture; TaskFile=$task; CliPath=$mock}
    & $runner @base -RunId plan -Mode plan | Out-Null
    if ((Read-WorkflowTask $task).status -ne 'ready') { throw 'Plan changed task state.' }
    & $runner @base -RunId implement -Mode accept-edits | Out-Null
    $data = Read-WorkflowTask $task
    if ($data.status -ne 'ready-for-verification' -or $data.attempts.Count -ne 1) { throw 'Implementation lifecycle failed.' }
    $meta = Get-Content -LiteralPath (Join-Path $fixture 'workflow/runs/implement/metadata.json') -Raw | ConvertFrom-Json
    if ($meta.taskId -ne 'TASK-001' -or $meta.attemptId -ne $data.attempts[0].attemptId) { throw 'Attempt identity failed.' }
    Assert-Rejected { & $runner @base -RunId duplicate-task -Mode accept-edits } '*Task cannot execute*'
    & $setter -ProjectRoot $fixture -TaskFile $task -Status needs-fix -Reason 'Independent check failed' | Out-Null
    '$global:LASTEXITCODE=1; ''{"status":"SUCCESS","response":"misleading"}''' | Set-Content -LiteralPath $mock
    Assert-Rejected { & $runner @base -RunId repair -Mode accept-edits } '*Dispatch did not complete*'
    $data = Read-WorkflowTask $task
    if ($data.status -ne 'failed' -or $data.attempts.Count -ne 2 -or $data.history.Count -ne 6) { throw 'Repair history not preserved.' }
    & $setter -ProjectRoot $fixture -TaskFile $task -Status ready -Reason 'Reviewed partial changes; safe to retry' | Out-Null
    if ((Read-WorkflowTask $task).status -ne 'ready') { throw 'Persisted recovery transition failed.' }
    $handle = [IO.File]::Open((Join-Path $fixture 'workflow/runs/active.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { Assert-Rejected { & $setter -ProjectRoot $fixture -TaskFile $task -Status blocked -Reason locked } '*used by another process*' } finally { $handle.Dispose() }
    '$global:LASTEXITCODE=0; ''{"status":"SUCCESS","response":"done","denied_actions":[{"action":"command"}]}''' | Set-Content -LiteralPath $mock
    Assert-Rejected { & $runner @base -RunId denied -Mode accept-edits } '*Dispatch did not complete*'
    if ((Read-WorkflowTask $task).status -ne 'blocked') { throw 'Permission failure did not block task.' }
    & $setter -ProjectRoot $fixture -TaskFile $task -Status ready -Reason 'Access restored' | Out-Null
    $saved = [IO.File]::ReadAllText($task)
    '<!-- workflow-task invalid -->' | Set-Content -LiteralPath $task
    Assert-Rejected { & $runner @base -RunId malformed-task -Mode accept-edits } '*malformed workflow-task header*'
    [IO.File]::WriteAllText($task, $saved)
    'PASS: approval, dependencies, duplicate Task IDs, transitions, plan isolation, attempts, repair history, and retry state.'
} finally {
    $target = [IO.Path]::GetFullPath($fixture)
    $prefix = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    if ($target.StartsWith($prefix, (Get-WorkflowPathComparison)) -and (Split-Path $target -Leaf) -like 'agentworkflow-state-*') { Remove-Item -LiteralPath $target -Recurse -Force }
}
