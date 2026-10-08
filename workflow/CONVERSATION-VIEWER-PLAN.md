# Antigravity conversation viewer

Status: approved by the user ("ok go on"); implemented; validation recorded in DASHBOARD.md.
Date: 2026-10-09 (Africa/Cairo).

## Requested outcome

Developers can open a local page, see project progress, tasks/dependencies, blockers/next steps, documents and verification records, then select a workflow run to see its exact prompt, response updates, tools, diagnostics, and final result. Recorded runs are grouped by conversation. The approved first version is read-only; launching tasks or sending messages remains a separate feature.

## Architecture

Antigravity CLI stream-json -> existing PowerShell adapter -> persisted events.ndjson -> local Node HTTP service -> SSE -> browser page.

Keep the existing runner as execution owner, including its approval/dependency gates, locks, timeouts, and independent verification. Add an optional streaming output setting without changing the existing JSON default. Save raw events as they arrive and extract the final result into the existing stdout.json contract. Keep stderr diagnostics separate. The viewer observes supported workflow runs; it does not attach to arbitrary IDE conversations or expose unreported model internals.

Use Node built-in HTTP and file APIs and plain HTML/CSS/JavaScript, with no external packages or database. Bind the service to localhost and serve the page and SSE endpoint from the same origin. This is a local repository feature because the service needs the installed CLI and local run evidence.

## Page

- Sidebar: tasks/runs, current state, and recorded conversation grouping.
- Main timeline: exact dispatched prompt, assistant response steps, tool calls/results, errors, and final response.
- Run details: Task/Run/Attempt IDs, conversation ID, model, duration, verification state, and evidence availability.
- Controls: select run, pause auto-scroll, reconnect, expand tool details, and toggle diagnostics.
- States: no runs, waiting for events, connected, reconnecting, completed, interrupted, permission failure, and malformed event warning.
- Responsive layout, keyboard-accessible controls, readable contrast, and text rendering that does not execute model/tool HTML.

## Streaming and recovery

Antigravity documents init, step_update, and result NDJSON events. Agent response steps may supply text_delta fragments; tool steps may supply tool_info. The page displays only fields actually emitted by the CLI. SSE events have stable sequence IDs. On reconnect, Last-Event-ID replays stored events without duplicates. Historical JSON runs display their saved prompt and final response even without incremental events.

Never invent completion percentages. Show the current step, elapsed time, and actual events. Preserve successful execution versus independent verification as separate states. Conversation history means recorded workflow turns linked by conversation ID; importing prior external conversation history is outside this initial scope.

## Implementation increments

1. Add opt-in NDJSON capture to the adapter and preserve final-result compatibility, timeout behavior, and legacy JSON mode.
2. Add a localhost read-only run/history API and reconnectable SSE endpoint with bounded buffers and project-contained paths.
3. Build the conversation timeline and run selection UI; present for developer review.
4. Test partial lines, deltas, final-result extraction, malformed events, reconnect/replay, concurrent viewers, path traversal rejection, history grouping, timeout/interruption, and existing runner regressions.
5. Document launch commands and verify the page in a browser. Use a bounded live read-only CLI smoke test when access permits; label mock and live evidence separately.

## Evidence and unresolved choice

Installed agy --help confirms --output-format stream-json and --conversation. Official event documentation: https://antigravity.google/docs/cli/headless/ . A live streaming invocation has not yet been performed.

The user approved the expanded read-only dashboard after adding current project progress. Implementation uses existing workflow files and runner ownership. No public deployment or task launching was approved.
