# Copy this framework and start

## New project

1. Create a project directory.
2. Copy the top-level workflow templates and `scripts` into the project as `workflow`, excluding CONNECTION-TEST.md, PILOT-REPORT.md, existing runs, and prior tasks. Create an empty `workflow/tasks` directory. See the repository README for Windows and Linux copy commands.
   Exclude generated runs, connection-test records, smoke-test tasks, and previous application tasks. See EXECUTION.md.
3. Open the project directory in your coding tool and start a chat with the coordinator.
4. Paste the start prompt below, replacing the project path and idea.

## Existing project

Copy `workflow` into the existing project without overwriting an existing workflow directory. If one already exists, resume it or ask the coordinator to reconcile the templates with its current state. Open the project and use the same prompt, describing the change.

## Start prompt

> Use the framework in <absolute project path>/workflow. Read START-HERE.md, LIFECYCLE.md, and the other workflow documents. This is a fresh copy of the reusable starter; initialize PROGRESS.md for this project and preserve the templates' structure. I want to <describe the project or change>. Discuss requirements, use cases, design, and architecture with me before implementation. Write our decisions into the Markdown files and present them for review. Then prepare small numbered Antigravity assignments, verify the returned work independently, and maintain progress until my final review. Check whether an Antigravity connection is actually available and report its status accurately.

On a fresh copy, the coordinator replaces the starter's setup history with project-specific progress. Leave unknown sections explicitly unfilled until discussed. A copied starter is not evidence that work was implemented or accepted.

On Windows and Linux, install PowerShell 7.2+ and authenticate Antigravity CLI locally. Keep config.json's cliPath empty for platform discovery, or set an absolute path for this machine. See LINUX.md for Bash examples and Linux validation.

For projects with a UI, use Stitch MCP during planning following STITCH-UI-UX.md. Produce specific screen designs and interaction specifications, review them with the user, then include the chosen references in Antigravity tasks. Check tool availability in each new session; do not assume a copied folder provides a connection.

Include project-specific CI following CI.md. Inspect an existing pipeline or create one suited to the project's stack/provider. Verify clean dependency installation, required checks, and hosted run results when available; report merge-protection setup separately.

## Resume prompt

> Resume this project using <absolute project path>/workflow. Read progress, the spec, use cases, design, architecture, and active task evidence. Confirm the actual project state and continue the next eligible step.

## Expected sequence

Discussion -> requirements and use cases -> design and architecture -> your review -> task plan -> Antigravity implementation -> coordinator verification and repairs -> your final review -> authorized release.

The coordinator maintains the documentation. Antigravity records task results. You provide product decisions and reviews. Automatic handoff requires an established, tested connection; manual handoff can use ANTIGRAVITY-HANDOFF.md.
