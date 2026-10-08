# Skill guidance

Source inspected: [mattpocock/skills](https://github.com/mattpocock/skills), main branch, 2026-10-08. Upstream can change. This workspace uses adapted guidance; it does not contain an installed copy of those skills. Native loading in Antigravity has not been tested.

## Resources read

- [to-spec](https://github.com/mattpocock/skills/blob/main/skills/engineering/to-spec/SKILL.md): informs synthesis of requirements, design decisions, testing decisions, and exclusions.
- [to-tickets](https://github.com/mattpocock/skills/blob/main/skills/engineering/to-tickets/SKILL.md): informs one-file-per-task tracking, small complete behaviors, and explicit dependencies.
- [tdd](https://github.com/mattpocock/skills/blob/main/skills/engineering/tdd/SKILL.md): informs tests through public behavior and incremental test/implementation cycles.
- [handoff](https://github.com/mattpocock/skills/blob/main/skills/productivity/handoff/SKILL.md): informs concise context transfer through artifact references and suggested skills.

## Routing

Coordinator uses specification and task decomposition guidance while planning. Antigravity receives implementation/testing guidance relevant to the assigned outcome. When using the full upstream TDD skill, read its linked tests.md and mocking.md as well. Fetch and read any additional skill before assigning it; its title alone is not sufficient guidance.

## Deliberate adaptations

We use persistent workspace handoffs because shared Markdown is the user's requested workflow; upstream handoff instead saves a temporary document. Local task files are our issue tracker, with the coordinator maintaining the summary. We document agreed testing boundaries during planning and use proportionate verification for small edits. We are using these resources as a guide rather than invoking their full interview, publishing, or installation procedures.

## Installing later

Once Antigravity's supported skill format/location is known, select the needed skills, include their supporting resources, record the upstream revision, and verify loading with a small assignment. Never report skills as installed or active merely because a prompt links to them. No global installation or Antigravity configuration was changed during this documentation step.
