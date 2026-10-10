#requires -Version 7.2
function Get-WorkflowRevision {
    param([string]$Root)
    $command=Get-Command git -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) { return $null }
    $savedExit=$global:LASTEXITCODE
    try {
        $head=& $command.Source -C $Root rev-parse HEAD 2>$null
        if ($LASTEXITCODE -eq 0) { return "$head" }
        return $null
    } catch { return $null }
    finally { $global:LASTEXITCODE=$savedExit }
}
function Assert-WorkflowReviewer {
    param($Evidence, $Metadata, $Snapshot)
    $author=if ($Metadata.executorIdentity) { $Metadata.executorIdentity } else { 'antigravity' }
    $authorContext=if ($Metadata.conversationId) { $Metadata.conversationId } else { $Metadata.attemptId }
    if ($Evidence.reviewer.id -isnot [string] -or $Evidence.reviewer.contextId -isnot [string] -or [string]::IsNullOrWhiteSpace($Evidence.reviewer.id) -or [string]::IsNullOrWhiteSpace($Evidence.reviewer.contextId)) { throw 'Reviewer identity and context must be nonempty strings.' }
    $Evidence.reviewer.id=$Evidence.reviewer.id.Trim(); $Evidence.reviewer.contextId=$Evidence.reviewer.contextId.Trim()
    if ($Evidence.reviewer.id -eq $author.Trim() -or $Evidence.reviewer.contextId -eq $authorContext) { throw 'Review requires a different reviewer identity and execution context.' }
    if (-not $Evidence.ContainsKey('reviewedRevision') -or $Evidence.reviewedRevision -cne $Snapshot.revision -or $Evidence.testedFingerprint -ne $Snapshot.fingerprint) { throw 'Reviewer must attest to the exact current revision and file fingerprint (null revision for a project without HEAD).' }
}
function Assert-WorkflowGovernanceRecords {
    param([string]$Root, $Entry)
    foreach ($kind in @('decisionRecords','migrationPlans')) {
        $records=$Entry[$kind]
        if ($null -ne $records -and $records -isnot [array]) { throw "Invalid $kind array." }
        $required=if ($kind -eq 'decisionRecords') { $Entry.requiresDecisionRecord } else { $Entry.requiresMigrationPlan }
        if ($null -ne $required -and $required -isnot [bool]) { throw 'Governance requirement flags must be booleans.' }
        if ($required -and -not $records.Count) { throw "Task $($Entry.taskId) requires $kind." }
        foreach ($reference in $records) {
            $path=Resolve-WorkflowLocalPath $Root $reference.file
            if ($reference.hash -notmatch '^[A-Fa-f0-9]{64}$' -or -not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $reference.hash) { throw "Approved $kind record missing or changed: $($reference.file)" }
            $record=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable
            if ($record.schemaVersion -ne 1 -or $record.taskIds -isnot [array] -or $Entry.taskId -cnotin $record.taskIds -or [string]::IsNullOrWhiteSpace($record.approvalReference)) { throw 'Governance record requires schema, task linkage and approval.' }
            if ($kind -eq 'decisionRecords') {
                if ($record.decisionId -notmatch '^ADR-[A-Za-z0-9_-]+$' -or $record.status -cne 'accepted') { throw 'Decision must be accepted before implementation.' }
                foreach ($field in @('title','context','decision','alternatives','consequences','author')) { if ([string]::IsNullOrWhiteSpace($record[$field])) { throw "Decision is missing $field." } }
            } else {
                if ($record.migrationId -notmatch '^MIG-[A-Za-z0-9_-]+$' -or $record.status -cne 'approved' -or $record.scope -isnot [array] -or -not $record.scope.Count) { throw 'Invalid approved migration plan.' }
                foreach ($field in @('description','risk','backupPlan','rollbackProcedure','monitoring','rollForwardPlan')) { if ([string]::IsNullOrWhiteSpace($record[$field])) { throw "Migration is missing $field." } }
                foreach ($file in $record.scope) { if ($file -cnotin $Entry.allowedFiles) { throw 'Migration scope exceeds task editable files.' } }
                $validationPath=Resolve-WorkflowLocalPath $Root $record.rollbackValidationFile
                if ($record.rollbackValidationFile -cnotmatch '^workflow/runs/') { throw 'Rollback validation evidence belongs in the run evidence store.' }
                $validation=Get-Content -LiteralPath $validationPath -Raw | ConvertFrom-Json -AsHashtable
                $procedureHash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($record.rollbackProcedure)))
                if ($validation.schemaVersion -ne 1 -or $validation.migrationId -cne $record.migrationId -or $validation.status -cne 'passed' -or $validation.rollbackHash -ne $procedureHash -or [string]::IsNullOrWhiteSpace($validation.verifiedBy) -or [string]::IsNullOrWhiteSpace($validation.evidence) -or $validation.inputFiles -isnot [System.Collections.IDictionary] -or -not $validation.inputFiles.Count) { throw 'Migration needs independently recorded rollback validation for the approved procedure and its inputs.' }
                foreach ($file in $validation.inputFiles.Keys) {
                    $inputPath=Resolve-WorkflowLocalPath $Root $file
                    if (-not (Test-Path -LiteralPath $inputPath -PathType Leaf) -or (Get-FileHash -LiteralPath $inputPath -Algorithm SHA256).Hash -ne $validation.inputFiles[$file]) { throw "Rollback validation input is stale: $file" }
                }
            }
        }
    }
}
