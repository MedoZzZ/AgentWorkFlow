# Project design

Status: template, unfilled.

UI projects use Stitch MCP during planning. Follow STITCH-UI-UX.md. Define UX behavior in this document, generate screen proposals in Stitch, and record the selected version after user review. A generated screen alone does not establish working interactions or accessibility.

## Experience and visual direction

Record user goals, reference material, style preferences, and relevant accessibility/responsive requirements.

Record colors by role/value, typography sizes/weights, spacing, grid/container widths, corner radii, component variants, icon/asset sources, and themes. Preserve the existing design system for edits unless a redesign is agreed.

## Screens or interaction surfaces

For each screen, command, or other interface: purpose, related use cases, main actions, information shown, and navigation. For nonvisual projects, describe the relevant API/CLI interaction instead of inventing screens.

## Screen specification UI-001: <name>

- Related use cases and requirements:
- Route/entry point and permitted roles:
- Content hierarchy and layout:
- Components and exact labels/representative content:
- Action -> result/destination for each control:
- Field rules, validation, and feedback:
- Loading, empty, success, error, disabled, and permission states:
- Desktop/mobile behavior and agreed viewport sizes:
- Keyboard/focus behavior and accessible names:
- Stitch project/screen IDs and preview references:
- Selected design version/date:
- Implementation acceptance checks:

Repeat per relevant screen. Mark inapplicable states explicitly.

## States and flows

Describe loading, empty, success, error, validation, and permission states where relevant. Include navigation/flow diagrams and wireframes or a prototype when useful. Link previews and record which version the user reviewed.

## Existing-project changes

Record the current design conventions, what changes, and what stays unchanged.

## Review

- Proposed approach and tradeoffs:
- User feedback:
- Agreed version/date:
- Remaining questions:

## Implementation handoff and verification

Link the chosen Stitch screens and any retrieved screenshot/HTML artifacts. Record their retrieval date and the reviewed version; URLs alone may change or expire. Treat generated HTML as reference material to adapt to the project's stack and component conventions.

Each UI task references the relevant screen IDs, tokens, states, and interaction checks. Coordinator compares the implemented screens with the chosen design at agreed viewports and tests the actual user journey, keyboard access, and error behavior. Record intentional deviations and reasons; seek user review when they alter the agreed design.
