# Project continuous integration

Status: template. No runnable pipeline has been configured for an application yet.

## Project configuration

- Repository host and CI provider:
- Application stack and supported runtime versions:
- Package manager/version and lockfile:
- Working directory or monorepo packages:
- Exact install, lint, type-check, test, and build commands:
- Required environment variables and test services (names only, no secret values):
- Triggers: pull requests and changes to the main/integration branch; additional triggers when needed:
- Required checks before merge:

## Establish the pipeline

Coordinator includes CI design in architecture and task planning. Antigravity creates a runnable provider configuration suited to the actual repository. Establish it early, once the project has executable checks. Start with a minimal useful pipeline and add checks as features land.

1. Check out the intended revision and set the working directory explicitly.
2. Install a pinned supported runtime and the chosen package manager.
3. Install dependencies using the committed lockfile and the package manager's immutable/frozen install mode. Use the project's equivalent for stacks without that option. Cache by runtime and lockfile; a cache must not hide missing declared dependencies.
4. Run the relevant static checks, behavior tests, and production build. Include integration/browser tests for critical journeys as they become available. Do not add empty test suites merely to create a green check.
5. Preserve genuine failure exit codes. Required failing checks must fail the pipeline; do not use continue-on-error, skip failures, or weaken assertions to make it green.
6. Upload useful test reports and failure evidence, with secrets and private data excluded. Set reasonable timeouts and cancel superseded runs when supported.

Use the project's actual commands and scripts; verify paths and configuration from a clean checkout. Document baseline failures separately. A required check that was skipped, canceled, or never run is not a pass.

## Dependency and package failures

For failed installs, missing packages, incompatible versions, or lockfile mismatches, retain the failing command/log and diagnose the cause. Declare dependencies in the correct package, update the lockfile intentionally, and rerun clean installation plus affected tests/build. Avoid depending on globally installed tools or local-only files.

Select dependency-update and vulnerability checks appropriate to the host/stack. Record a policy for actionable findings; do not claim that automated scans establish complete security. Major upgrades and breaking changes must be verified against affected behavior.

For new or changed dependencies, also review exact package identity/source, possible misspellings or impersonation, unexpected transitive changes, and install scripts. Add ecosystem-appropriate malicious-package detection when supported. Record tool limitations: a vulnerability scan does not establish that a package is malware-free. Block known malicious dependencies and investigate suspicious findings before accepting the change; retain findings and fix evidence.

## Coordinator verification

- Pipeline config and scripts inspected:
- Clean install/local equivalent result:
- CI run URL and tested revision:
- Required check results:
- Artifacts inspected:
- Any unavailable checks/access:
- Verdict:

Verify the actual hosted run when access permits. If only local checks ran, label hosted CI unverified. Configuration existing on disk is not evidence of a passing run. If code changes after the run, require new evidence for the updated revision.

## Merge and delivery

Where repository access and authorization permit, configure required status checks/branch rules so required failures prevent merging. CI configuration alone does not enforce a merge restriction. Record protection as configured, pending, or unavailable. User review follows verification; deployment is a separate authorized step.

## Failure loop

CI failure -> coordinator diagnoses and assigns repair -> Antigravity fixes -> local checks -> hosted CI rerun -> coordinator verifies evidence. Follow LIFECYCLE.md's repair limit and preserve earlier failures in the task history.
