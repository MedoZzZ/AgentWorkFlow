# Local developer dashboard

The read-only dashboard displays current project progress, task states and dependencies, attempt/repair history, independent verification results, source documents, run evidence, and Antigravity conversations. It reads the existing files; it does not approve work or launch tasks.

## Start

Requires Node 18.18+ (tested locally with Node 22.16.0) and PowerShell 7.2+ for executor scripts. No package installation or database is needed.

```powershell
node ./workflow/dashboard/server.mjs --project-root 'C:/Projects/MyApp' --port 4317
```

Open http://127.0.0.1:4317 . On Linux use the same Node command with the Linux project path. Omitting --project-root selects the project containing this workflow. Keep the terminal running; Ctrl+C stops the service. Use --port to select another local port. The service binds only to 127.0.0.1 and rejects foreign Host/Origin headers. It has no public deployment or authentication layer and should not be exposed through a proxy or port forwarding.

## Capture a live conversation

```powershell
./workflow/scripts/Run-Antigravity.ps1 -ProjectRoot 'C:/Projects/MyApp' -TaskFile 'C:/Projects/MyApp/workflow/tasks/TASK-001.md' -RunId TASK-001-01 -Mode plan -Stream
```

For approved implementation use the existing -Mode accept-edits gates. -Stream selects Antigravity's supported --output-format stream-json. Default JSON mode is unchanged. Native executables support streaming; in-process .ps1 mock CLIs remain JSON-only. The adapter continuously flushes stdout events to events.ndjson and stderr to stderr.log while preserving normal timeouts/permissions and final stdout.json compatibility. Malformed streams or missing/duplicate final result events fail the run. A timeout retains received events.

SSE carries persisted NDJSON to the browser. Partial lines wait until complete. Sequence IDs support Last-Event-ID replay, manual reconnect, and multiple viewers. Slow clients are disconnected when queued output exceeds the limit. Event lines above 2 MiB are omitted with a visible warning; raw local evidence remains intact. Source/evidence files displayed through the API have a 2 MiB limit, and diagnostics retain the latest 2 MiB. Reading is bounded per tick. Historical JSON runs show their exact prompt and saved final response, without invented intermediate activity.

## Views

- Overview: actual managed-task counts, current verified scope, blockers/reviews, progress notes and next steps, recent runs.
- Tasks: state/title filters, dependencies, attempts, full task specifications and transition history. Headerless tasks are explicitly unmanaged.
- Conversations: recorded turns grouped by conversation ID, exact dispatched prompts, response fragments, collapsible tool output, diagnostics toggle, auto-scroll control, reconnect, run IDs/model/state/elapsed time and changed files. Up to 20 earlier turns are shown for context.
- Verification: passed/failed/skipped/unavailable checks, acceptance evidence, tested revision/file fingerprint, and stale scoped verification indication. Execution SUCCESS remains distinct from coordinator verification.
- Documents: PROGRESS.md, PROJECT-SPEC.md, USE-CASES.md, DESIGN.md, ARCHITECTURE.md, and CI.md, rendered as safe text/basic Markdown. Model/file HTML is never executed.

The dashboard observes this project's recorded workflow runs. It does not attach to unrelated Antigravity IDE chats, import external conversations, expose unreported model reasoning, or invent completion percentages. Roles shown in navigation describe responsibility; they are not proof of an authenticated connector.

## Design reference

Stitch project: 18323338688219883686; screen: dce7b56a92e4441fb287b9f3114cab3f; design system: assets/7bf3411b4d60496ab71302992c40deaa. The generated reference uses an ink/navy surface, mint status accents, a navigation rail, task metrics, live conversation panel and run inspector. The implementation adapts that hierarchy to the approved overview/tasks/conversation/verification/document views. Illustrative design counters, fabricated model/version/throughput values, and unreported reasoning were excluded. The user's approval covered this dashboard scope; the generated reference is not recorded as a separately approved visual version.

## Validation

- Existing configuration, lifecycle, and evidence suites pass locally on Windows.
- Test-Streaming.ps1 verifies a real local pwsh emitter flushes events before completion, captures text deltas/diagnostics, normalizes the final result, rejects malformed streams, and enforces timeout while retaining partial events.
- Dashboard Node tests cover actual overview/status data, partial UTF-8 event lines, replay, concurrent viewers, project updates, JSON history, verification freshness, invalid task headers, oversized events, and traversal/foreign-origin/symlink rejection.
- Browser QA inspected overview, task/history, verification and documents, plus the mobile layout (no horizontal overflow). An isolated synthetic browser fixture verified response fragments combine into one message, manual reconnect does not duplicate responses, tool output remains inert text, and the final result preserves pending verification. The fixture and its server were removed. No browser console errors were observed. The failed live CLI run appeared with its actual prompt, streamed result error, and pending verification.
- Live Antigravity smoke run dashboard-stream-smoke-01 failed because sandbox network access was blocked. Automatic approval review rejected the network-enabled retry because the task prompt and potentially private workflow contents would be sent to Google without specific payload authorization. No successful live model response is claimed. The model-independent streaming path is tested.
- CI includes the new suites on Windows and Ubuntu; hosted results and a new Linux run remain pending.

Official stream contract: https://antigravity.google/docs/cli/headless/ . Local run logs may contain private prompts/output; keep them local and review before sharing.

## Workflow controller status

The overview includes approved workflow checkpoints and the read-only /api/workflows endpoint. The existing project SSE feed carries controller phases, pending/currently verified tasks, active run and attempt, limits, repair/review history, final-review status and stop reasons. No execution controls were added. See ORCHESTRATION.md and LINUX.md for startup and coordinator actions. Restart an already running server to load the updated API code; then reload the page. These controller/dashboard additions were not tested at the user's request.

## Portfolio and governance

The dashboard adds All projects, a registered-project selector, and Decisions & release. /api/projects aggregates registered workspaces; /api/governance returns decision, migration and release records. Selected-project API/SSE requests carry projectId, and portfolio=1 selects portfolio SSE. Registry entries explicitly permit local reads and never trigger project execution. Review evidence shows reviewer identity/context and revision; schema-2 reviews are flagged stale after revision, scoped-file, requirement or dependency-linkage changes. Release reports are historical and must be reevaluated before any release operation. See GOVERNANCE.md. Restart an existing server and reload the page for the new API/UI. Testing remains deferred.
