# Reviews, decisions, migrations and release

These additions adapt the governance concepts discussed during the ApexYard comparison to the existing PowerShell/Node framework. They add local gates and records; they do not install ApexYard, Git hooks, branch protection, a detached reasoning service, or deployment automation. Tests and runtime validation were deferred by the user's instruction.

## Independent reviews

New workflow drafts set governance.requireReviewerIdentity to true. Use REVIEW-TEMPLATE.json (schemaVersion 2) instead of the legacy verification template. Record the actual reviewer.id and reviewer.contextId: they must differ from Antigravity's executor identity and conversation/attempt context. reviewedRevision must equal the current Git HEAD, or null if there is no committed baseline. The existing testedFingerprint and taskScopeHash bind the reviewed file state and requirements. Missing evidence never defaults to a passing verdict.

The identities are submitted attestations. The scripts reject identical author/reviewer identities and contexts and record who claimed the review, but they do not authenticate the caller or prove an isolated review context. Use a real separate reviewer context where required; do not invent IDs to satisfy the fields. Strong isolation would need a trusted coordinator integration and access controls outside this shared workspace.

Record-Verification supports schema 1 for compatibility and schema 2 for identity/revision binding. The controller requires schema 2 when the approved plan enables it. Schema-2 reviews become stale after HEAD changes or relevant scoped files/requirements change. Strict plans also reject legacy dependency reviews lacking identified reviewers. Recheck those tasks in approved scope before relying on them.

Use -Action Recheck with a coordinator decision containing the same identity/fingerprint/boundary fields as a repair decision, action recheck, and findings explaining why the existing implementation needs new independent evidence. The controller moves a previously successful attempt back to ready-for-verification and reruns its approved checks without dispatching Antigravity or consuming another implementation attempt. Older check results remain in per-pass directories. Use Repair for actual implementation defects. No-attempt, failed or partially interrupted work cannot bypass repair diagnosis through Recheck.

Final reviews use FINAL-REVIEW-TEMPLATE.json. Strict plans also require reviewer identity/context and reviewedRevision at final review. technical completion is separate from user acceptance and authorization to release.

## Technical decision records

Copy DECISION-TEMPLATE.json, fill context, decision, alternatives, consequences, author and linked taskIds, and obtain approval for accepted decisions. Save the input in a temporary location or workflow/runs so a disposable input does not become project source.

```powershell
./workflow/scripts/Record-Decision.ps1 -ProjectRoot . -InputFile workflow/runs/decision-input.json
```

The script writes an immutable workflow/decisions/ADR-ID.json and returns its file/hash reference. New decisions supersede older ones through the supersedes field rather than overwriting their history. For architectural tasks, set requiresDecisionRecord true and include the returned reference in decisionRecords in the approved workflow plan. The controller validates accepted status, linkage, content, approval and exact hash before work. Optional decisions can be linked the same way. Changes to approved records require a newly approved plan.

## Migration gate

Copy MIGRATION-PLAN-TEMPLATE.json into workflow/migrations/MIG-ID.json. Record scope, risk, backups, rollback procedure, monitoring and roll-forward approach. Record user approval and set status approved only after actual review. Set requiresMigrationPlan true and reference the approved file/hash in the task's migrationPlans array. Its scope must fit the task's exact allowedFiles.

The gate requires rollback validation evidence under workflow/runs, using ROLLBACK-VALIDATION-TEMPLATE.json. A passing record must identify the verifier, describe actual evidence, match the SHA256 of the exact UTF-8 rollback procedure, and include current input-file hashes. Use stable fixtures and procedure inputs; changed inputs invalidate validation. A placeholder, unavailable result or stale evidence blocks dispatch. The framework validates supplied evidence; it does not execute a database rollback or independently establish its safety. No rollback test was run during this build.

Governance requirement flags are explicit in the approved task manifest. The framework does not infer every architectural or database change from filenames; the coordinator must classify work during planning and include the required records.

## Release gate

Copy RELEASE-PLAN-TEMPLATE.json to a project-specific release plan. Choose an explicit releaseId, target, completed workflowIds and required readiness checks. The template includes security, performance, accessibility, monitoring, documentation and QA acceptance; customize those checks before approval for the actual product.

Use RELEASE-EVIDENCE-TEMPLATE.json for the actual evidence under workflow/runs. It requires passing evidence for every required check, the release-plan hash, exact project fingerprint/revision, an independent reviewer, and a human approval reference naming this release, target and fingerprint. Plan approval does not automatically fill release approval.

```powershell
./workflow/scripts/Check-Release.ps1 -ProjectRoot . `
  -PlanFile workflow/RELEASE-PLAN.json -EvidenceFile workflow/runs/release-evidence.json
```

The evaluator holds the project lock and validates workflow completion, current task reviews, governance records and final scope evidence. Reports are immutable under workflow/runs/_releases/RELEASE-ID with a latest.json pointer. Missing/stale evidence yields a persisted blocked report and a failing script exit. Success reports ready-for-authorized-release and actionExecuted false. It never merges, migrates or deploys, and is not a hook intercepting arbitrary Git/GitHub commands. Actual release operations require a separate authorized integration to enforce this gate immediately before acting.

Store release plans as stable source and evidence under the excluded run store. Recheck before release after any source or revision change. Dashboard reports are historical evidence, not continuously granted release permission.

## Shared project registry

Register each local project explicitly from the dashboard's home workspace:

```powershell
./workflow/scripts/Register-Project.ps1 -ProjectRoot . -Id billing -Name 'Billing app' -Path 'C:/Projects/Billing'
```

On Linux, supply native absolute paths such as /home/user/projects/billing. The command writes workflow/projects.json, a local gitignored registry excluded from source fingerprints. It preserves other entries and rejects duplicate paths/IDs. Re-register an ID to update its name/path/status; -Status archived marks it archived without moving or deleting files. The dashboard always includes its home workspace as local. PROJECT-REGISTRY-TEMPLATE.json provides an empty portable schema, not machine-specific paths.

The All projects view aggregates recorded task counts, blockers, workflows and release reports. The project selector switches the existing task/conversation/verification/document views to a registered project. API requests use projectId, never an arbitrary filesystem path. /api/projects supplies the portfolio; /api/governance supplies decisions/migrations/releases; project SSE carries updates and portfolio=1 supplies portfolio SSE. Conversation replay stays scoped to the selected project. Registrations are read permissions for the local dashboard, not authorization to execute tasks there.

The service remains on 127.0.0.1 with GET-only APIs and local same-origin checks. No remote publishing or project execution controls were added. Restart a running server to load these additions. Register at most 50 projects per registry; inaccessible roots appear unavailable. Native paths must be re-registered when moving a workspace between operating systems.
