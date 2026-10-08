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
- `START-HERE.md`: copying this starter and beginning a new chat.
- `TASK-TEMPLATE.md`: copy into `tasks/TASK-001.md` for each assignment.
- `ANTIGRAVITY-HANDOFF.md`: execution instructions and return format.
- `SKILL-GUIDE.md`: source skills and how to use them.

Use local Markdown as the issue tracker. The individual task file is the source of truth for task status; PROGRESS.md is the summary. Keep application projects in their own directories and copy this workflow into them. Do not treat this workflow workspace as an application already under development.

## Current integration limit

Antigravity CLI connection and shared-workspace reading passed a read-only test; see CONNECTION-TEST.md. Application edits, command permissions, skill loading, and repair continuation still need verification. Use the recorded CLI path when it is not available on PATH, and confirm availability in new sessions.

## Resume a session

Read PROGRESS.md, the project spec, use cases, design, architecture, the active task, and its latest evidence. Inspect actual files and Git state where available. Confirm that evidence matches the current changes before continuing. Never infer completion from a previous chat summary alone.
