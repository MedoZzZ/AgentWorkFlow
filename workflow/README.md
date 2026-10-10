# AI project lifecycle

Created: 2026-10-08 (Africa/Cairo). Status: workflow draft ready for discussion.

The user sets product direction and accepts the result. The coordinator plans and verifies. Antigravity implements assigned work and returns evidence.

## Start here

- `LIFECYCLE.md`: stages, ownership, and completion rules.
- `PROGRESS.md`: what is done, active, next, and blocked.
- `PROJECT-SPEC.md`: requirements and acceptance criteria for the next project.
- `USE-CASES.md`: actors, journeys, alternative flows, and acceptance mapping.
- `DESIGN.md`: interaction design, screens, states, and visual direction.
- `STITCH-UI-UX.md`: Stitch generation, design review, and implementation handoff.
- `ARCHITECTURE.md`: components, data, interfaces, and technical decisions.
- `CI.md`: clean dependency installation, automated checks, failure handling, and merge requirements.
- `EXECUTION.md`: preflight, automated CLI dispatch, Git checkpoints, and evidence handling.
- `TASK-STATE.md`: managed task headers, transition commands, and legacy compatibility.
- `VERIFICATION.md`: file evidence, independent verification, repair limits, recovery, and adapter responsibilities.
- `ORCHESTRATION.md`: approved plans, sequential scheduler/controller, independent reviews, bounded repairs and recovery.
- `GOVERNANCE.md`: identified revision-bound reviews, immutable decisions, rollback/release gates and shared project registry.
- `WORKFLOW-PLAN-TEMPLATE.json`: task/file/command scope and budgets; New-WorkflowPlan.ps1 creates a draft with current hashes.
- `VALIDATION.md`: actual enhancement test results and unavailable checks.
- `DASHBOARD.md`: localhost project dashboard, SSE conversation capture, design references, and validation.
- `LINUX.md`: Linux setup, Bash commands, platform rules, and verification limits. Scripts require PowerShell 7.2+ on Windows and Linux.
- `config.json` and `CONFIGURATION.md`: editable defaults for the model, mode, timeout, CLI path, and discovery checks.
- `START-HERE.md`: copying this starter and beginning a new chat.
- `TASK-TEMPLATE.md`: copy into `tasks/TASK-001.md` for each assignment.
- `ANTIGRAVITY-HANDOFF.md`: execution instructions and return format.
- `SKILL-GUIDE.md`: source skills and how to use them.

Use local Markdown as the issue tracker. The individual task file is the source of truth for task status; PROGRESS.md is the summary. Keep application projects in their own directories and copy this workflow into them. Do not treat this workflow workspace as an application already under development.

## Current integration limit

Antigravity CLI reading, editing, scoped test execution, and follow-up continuation passed an isolated pilot; see PILOT-REPORT.md. Native skill loading and real project integrations still need verification. Confirm CLI availability and scoped command permissions in each new environment.

## Resume a session

Read PROGRESS.md, the project spec, use cases, design, architecture, the active task, and its latest evidence. Inspect actual files and Git state where available. Confirm that evidence matches the current changes before continuing. Never infer completion from a previous chat summary alone.
