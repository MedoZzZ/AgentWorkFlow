# Lifecycle and ownership

## 1. Discuss and understand

Coordinator and user clarify the problem, target users, desired behavior, constraints, priorities, and exclusions. Record unanswered questions instead of inventing answers. For an existing project, inspect its instructions, architecture, current behavior, uncommitted work, and baseline checks first.

## 2. Specify and plan

Before application implementation, coordinator fills PROJECT-SPEC.md, USE-CASES.md, DESIGN.md, and ARCHITECTURE.md with the user. Use cases define the actors, main flows, alternative/error flows, and expected outcomes. Design defines screens or interaction surfaces, navigation, and important states. Architecture defines system boundaries, modules, data flow, interfaces, deployment, and important tradeoffs. Use diagrams where they clarify the proposed system.

Present these artifacts for the user's review before assigning implementation. Record explicit agreement in PROJECT-SPEC.md. Unresolved questions that affect implementation must be resolved first. For small existing-project changes, document only the affected use cases, design, and architecture; mark unaffected sections as unchanged with a reason rather than inventing a redesign.

For UI projects, use Stitch MCP following STITCH-UI-UX.md to make screen designs concrete before implementation. DESIGN.md specifies layouts, components, content, actions, states, visual tokens, responsive behavior, and relevant accessibility checks. Record selected Stitch screens after user review and include those references in UI assignments. Verify the implemented appearance and interactions against that agreed design.

After that review, create one task file per small, verifiable outcome. Record dependencies and acceptance criteria. Prefer tasks delivering a complete narrow behavior through the relevant layers. Scale documentation to the change.

Include project-specific CI following CI.md: reproducible dependency installation, appropriate static checks/tests/build, and actionable failure evidence. Establish or inspect the pipeline early. For existing projects, preserve useful checks and repair relevant pipeline gaps. Record the provider, exact commands, required checks, and merge-protection status.

Product choices that remain unresolved return to the user. Routine implementation choices within the agreed scope can proceed. Define testing boundaries in the plan; use existing project checks where appropriate.

## 3. Assign

Coordinator selects a ready task whose dependencies are verified. Send Antigravity the task path, project root, relevant instructions, selected skill guidance, and baseline revision or file state. Assign one task at a time initially. Record dispatch only after it actually occurs.

## 4. Implement and report

Antigravity reads the assignment, implements the numbered steps, runs appropriate checks, and records changes, commands, results, and limitations in the task file. It may mark ready-for-verification, but cannot mark verified. Preserve existing user changes. Report scope conflicts or missing access immediately.

## 5. Independently verify and repair

Coordinator inspects the actual diff and independently runs relevant checks when access permits. Check acceptance criteria and affected existing behavior; inspect a running preview for UI changes. Report skipped or unavailable checks as unverified.

Inspect CI results for the revision being verified. Required install, test, or build failures prevent verification. Fix package/lockfile/runtime/path problems through the repair loop. When hosted CI cannot be observed, report it as unverified even if local checks pass.

On failure, add a numbered repair round to the same task: failed criterion, observed evidence, expected behavior, and required recheck. Return it to Antigravity, then verify again. After three unsuccessful repair rounds, diagnose the underlying cause and revise the approach rather than repeating the same assignment. Missing access stops dependent execution and is recorded as blocked.

Do not weaken acceptance criteria or remove failing tests merely to obtain a pass. Requirement changes must be recorded with their reason and user agreement when they change product scope.

## 6. Milestone and final user review

Coordinator reviews the integrated result against the spec. Provide a runnable preview or reproduction steps, summary of changes, verification evidence, and known limitations. User feedback becomes repair work or a newly scoped task. User acceptance is recorded explicitly; silence does not count.

## 7. Release and maintain

When release is authorized, document deployment steps and recovery approach, release, and run a smoke check on the deployed result. Record release version or revision and remaining follow-ups. Bugs enter the same lifecycle with reproduction steps and regression checks.

## Task states

Managed task headers enforce [TASK-STATE.md](TASK-STATE.md). Use Set-TaskStatus.ps1 for coordinator transitions and Record-Verification.ps1 for verified verdicts; the runner manages execution attempts. [VERIFICATION.md](VERIFICATION.md) covers structured evidence, bounded repairs, and recovery inspection. Headerless legacy tasks remain unmanaged.

`draft -> ready -> in-progress -> ready-for-verification -> verified`

Verification failures: `ready-for-verification -> needs-fix -> in-progress`.

Any unfinished task may become `blocked`, with a specific reason and resume condition. The coordinator owns ready, needs-fix, and verified; the executor owns in-progress and ready-for-verification. Only verified tasks appear as done. User acceptance and release status are separate milestone records.
