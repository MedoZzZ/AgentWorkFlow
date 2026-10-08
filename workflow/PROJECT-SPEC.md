# Project specification template

Status: unfilled. No application scope has been agreed.

## Identity

- Project name:
- Project directory:
- New project or existing change:
- Source revision/baseline:

## Problem and desired outcome

Describe the user's problem and the behavior that solves it.

## Users and key journeys

Describe who uses the product and their main actions.

## Requirements

Assign stable IDs such as REQ-001. Include priority and observable acceptance criteria. Record error, empty, and boundary behavior where relevant.

## Constraints and exclusions

Record technology, compatibility, design, data, time, and cost constraints. State what is outside this delivery.

## Existing project baseline

Record how to run the app and checks, relevant modules, existing failures, and user changes that must be preserved.

## Design and testing decisions

Record module boundaries and public behavior to test. Match tests to risk. Use browser verification for relevant UI journeys. Mark unavailable checks explicitly. Record important decisions and shared terminology here; split them into glossary/decision files only when useful.

Define required CI checks in CI.md, including clean dependency installation and build/test commands. Record whether hosted CI and required merge checks can be configured and observed.

## Milestones and task dependencies

Link one file per task. Each task should be independently verifiable when practical.

## Before-implementation review

- Use cases: USE-CASES.md
- Interaction/visual design: DESIGN.md
- Technical architecture: ARCHITECTURE.md
- Status: not yet reviewed for an application project
- User agreement (date and actual instruction):
- Unresolved decisions that block implementation:

Do not dispatch application implementation until this review is complete.

## Open questions

List unresolved questions and which work depends on the answers.

## Acceptance and release

- Preview/reproduction method:
- Definition of delivery complete:
- User feedback and acceptance record:
- Release authorization and deployment method:
- Recovery procedure:
