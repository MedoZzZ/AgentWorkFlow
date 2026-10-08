# Framework settings

Edit workflow/config.json once to set defaults for every dispatch in that project. Keep your preferred defaults in the reusable starter before copying it. These settings do not change Antigravity's own global account configuration or projects that already have their own copy.

| Setting | Purpose |
| --- | --- |
| schemaVersion | Configuration format; leave at 1. |
| antigravity.model | Explicit model slug; default gemini-3.8-flash-high. Check agy models for current availability. |
| antigravity.mode | plan (read-only instructions) or accept-edits. Default plan; implementation still follows project review. |
| antigravity.timeoutSeconds | CLI print timeout, integer 10–3600; default 600. |
| antigravity.cliPath | Empty for PATH/platform discovery (`%LOCALAPPDATA%/agy/bin/agy.exe` on Windows, `~/.local/bin/agy` on Linux), or an absolute executable path. JSON Windows paths need doubled backslashes, or use forward slashes. For Linux overrides use `/home/yourname/.local/bin/agy`; literal `~` is not expanded in JSON. |
| preflight.runtimeCommands | Command names to discover; does not execute them or verify their versions. |
| preflight.manifestFiles | Root-level filenames to detect; does not inspect package contents. |

Runner precedence: explicit command arguments override config values. Both scripts accept -ConfigPath for a different complete configuration file, including a shared defaults file outside the project. There is no multi-file merging. Unknown or missing keys and invalid values stop execution before dispatch.

Examples:

```powershell
.\workflow\scripts\Preflight.ps1 -ProjectRoot 'C:\Projects\MyApp'
.\workflow\scripts\Run-Antigravity.ps1 -ProjectRoot 'C:\Projects\MyApp' -TaskFile 'C:\Projects\MyApp\workflow\tasks\TASK-001.md' -RunId 'TASK-001-round-01' -Mode accept-edits -Model gemini-3.8-flash-medium
```

Run metadata records the effective model, mode, timeout, and CLI path. Each run also saves a parsed config snapshot. The preflight report shows configuration defaults; effective argument overrides are in metadata.json. Model selection failures are surfaced rather than silently substituting a different model. A listed model is not proof of remaining quota or entitlement for a completed run.

Do not put credentials, API keys, or arbitrary shell commands in this file. It configures supported framework behavior; CI commands and design decisions remain in the relevant project documents.
