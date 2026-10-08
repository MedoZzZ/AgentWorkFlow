# Stitch UI/UX planning workflow

Preference: use Stitch MCP for UI design during project planning. Stitch tool definitions are available in this session; account access and generation have not been tested for a project. No Stitch project or screens were created for this reusable starter.

## 1. Prepare the brief

Read the spec and use cases. Fill DESIGN.md with audience, journeys, screen inventory, navigation, content hierarchy, layout constraints, visual direction, existing brand/components, responsive expectations, and accessibility requirements. Resolve important UX questions with the user. Use representative sample content rather than private production data.

## 2. Establish project and visual system

Check available Stitch projects and use the project's recorded ID when resuming. Create a project only for the actual design assignment. Inspect existing screens/design systems before edits. Record IDs in DESIGN.md.

Use a coherent design system across screens. For an initial screen, generate_screen_from_text can establish one; reuse its actual design-system reference for later screens. If creating a system with create_design_system, immediately follow with update_design_system as required by the tool. If uploading DESIGN.md, immediately follow upload_design_md with create_design_system_from_design_md using the returned screen instance.

## 3. Generate specific screen proposals

Give each prompt the screen's purpose, actor, mapped use case, layout, components, labels/content, important states, device type, and visual constraints. Generate the main journey first, then affected secondary screens and states. Use edit_screens for focused revisions and generate_variants when a concrete design choice needs comparison. Do not generate unrelated screens.

## 4. Inspect and review

Retrieve screen details/previews and inspect them against the brief. Check content hierarchy, consistency, missing states, and mobile adaptations. Present a concrete design for user review, revise feedback, and record the selected screen/version. Document interaction behavior that a static visual cannot demonstrate. UI implementation begins after the agreed design/architecture review.

## 5. Hand off and verify

Include relevant screen references, available screenshot/HTML artifacts, tokens, responsive rules, and behavioral criteria in the Antigravity task. Verify that Antigravity can access the references; provide shared artifacts or explicit specifications if it cannot. Do not assume Stitch access is shared between tools.

Antigravity adapts the reference to the project's stack and builds real behavior. Coordinator checks the rendered implementation against the selected design and independently exercises the mapped use cases. Visual resemblance and functional correctness require separate evidence.

## Failure and resume handling

Record unavailable access as a planning blocker; discuss a concrete fallback with the user rather than silently dropping Stitch. Follow the current tool instructions. Generation/edit calls may continue after a timeout: inspect existing project/screens and retrieve results before considering a new request. Preserve IDs, prompts, selected versions, and review decisions so resuming does not create duplicate work.
