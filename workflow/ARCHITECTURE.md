# Project architecture

Status: template, unfilled.

## Context and constraints

Define the system boundary, external services, existing architecture, and relevant scale, compatibility, security, or reliability requirements.

## Components and responsibilities

Describe major modules/services and why each exists. Add a Mermaid component diagram where useful. Prefer the simplest structure that supports the agreed requirements.

## Data and behavior

- Entities, relationships, ownership, and lifecycle:
- Flow through components for the main use cases:
- Public interfaces, API contracts, and error behavior:
- Authentication and authorization where applicable:
- External integrations and failure handling:

## Technology and tradeoffs

Record selected technologies, reasons, alternatives considered, and important assumptions. Preserve existing conventions unless the change requires a different approach.

## Execution and verification

- Local setup and runtime:
- Test boundaries and appropriate checks:
- CI provider, clean-install strategy, required checks, and merge protection (see CI.md):
- Deployment environments and configuration:
- Diagnostics/observability:
- Data migration and recovery where applicable:

## Review

- Decisions and rationale:
- User feedback:
- Agreed version/date:
- Remaining questions and technical risks:
