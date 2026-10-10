#requires -Version 7.2
param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9_-]+$')][string]$WorkflowId,
    [Parameter(Mandatory)][string[]]$TaskFiles,
    [string]$OutputFile='workflow/WORKFLOW-PLAN.json'
)
$ErrorActionPreference='Stop'
foreach ($file in @('Platform.ps1','Task-State.ps1','Evidence.ps1','Workflow-Plan.ps1')) { . (Join-Path $PSScriptRoot $file) }
$root=(Resolve-Path -LiteralPath $ProjectRoot).Path
$output=Resolve-WorkflowLocalPath $root $OutputFile
if (Test-Path -LiteralPath $output) { throw 'Plan already exists; preserve approval and history.' }
$entries=@(); $ids=@{}
foreach ($file in $TaskFiles) {
    $path=Resolve-WorkflowLocalPath $root $file
    $task=Read-WorkflowTask $path
    if ($ids.ContainsKey($task.taskId)) { throw 'Duplicate task in draft scope.' }
    $ids[$task.taskId]=$true
    $entries+=@{taskId=$task.taskId; file=$file; scopeHash=(Get-WorkflowTaskScopeHash $path); dependencies=@($task.dependencies); priority=0; allowedFiles=@(); checks=@(); acceptanceCriteria=@(); requiresDecisionRecord=$false; decisionRecords=@(); requiresMigrationPlan=$false; migrationPlans=@()}
}
if (-not $entries.Count) { throw 'Select at least one managed task.' }
$draft=@{schemaVersion=1; workflowId=$WorkflowId; approvalReference=''; coordinatorMode='active-session'; allowDeployment=$false; limits=@{maxRepairAttempts=3; taskTimeoutSeconds=600; workflowTimeoutSeconds=7200}; tasks=$entries}
$draft['governance']=@{requireReviewerIdentity=$true}
Write-WorkflowJson $output $draft
Write-Output "Draft created: $output. Fill exact editable files, approved checks and acceptance criteria; record user approval before Drive."
$global:LASTEXITCODE=0
