# SunderingTools Settings UI Redesign

**Context**

`SunderingTools` already has a tracker the user is happy with, but the addon configuration window still looks like a utilitarian prototype. The current `Settings.lua` mixes frame construction, styling, layout, and section rendering in one place, uses brittle manual anchoring, and does not yet support a professional minimap positioning flow.

The target is a settings shell that still feels at home in WoW, but with a clearer identity: dark base, restrained turquoise accents, concise copy, consistent spacing, and stable layout behavior as more modules are added.

**Goals**

- Redesign the settings window so it feels professional, stable, and intentional.
- Keep the overall visual language compatible with WoW instead of fighting it.
- Use the supplied turquoise, black, and white palette as the addon identity, with turquoise acting as an accent instead of flooding the UI.
- Give the addon and section copy more personality while staying concise and avoiding references to other addons.
- Make the settings content area scalable through scrolling so new modules can be added without redoing the shell.
- Add proper minimap icon controls, including visibility, drag/reposition support, and reset.
- Refactor the settings code so visual primitives, shell layout, and section content are separated cleanly.

**Non-Goals**

- Do not redesign the runtime tracker bars again as part of this task.
- Do not introduce external UI libraries or a full config framework.
- Do not turn the settings window into a highly ornamental fantasy panel that sacrifices clarity.
- Do not add speculative module features outside the existing settings surface.

**Visual Direction**

- Base theme: WoW-native dark paneling with sharper hierarchy and cleaner spacing.
- Accent usage: turquoise is reserved for active nav state, focused controls, selected values, hover treatment, and small visual markers.
- Typography: keep Blizzard-readable fonts, but tighten hierarchy so headers, body copy, values, and helper text read clearly at a glance.
- Tone: short labels, short descriptions, no references to competitor addons, no hype language.
- Frame personality: sturdier side navigation, clearer panel grouping, subtle texture/backdrop treatment, and action buttons that feel deliberate instead of generic.

**Window Structure**

- Left rail: fixed vertical module navigation.
- Right panel: scrollable content area that can grow with future modules.
- Header: addon title plus one concise line of context for the selected section.
- Footer or top action row: global actions such as edit mode toggle, reset, and minimap controls where appropriate.
- Content grouping: settings are presented in compact blocks instead of long unstructured stacks.

**Section Layout**

`General`

- Base addon controls.
- Global edit mode action.
- Global reset action.
- Minimap visibility and minimap positioning controls.
- Short usage/help copy where needed.

`Interrupt Tracker`

- Group controls into:
  - state/actions
  - layout/size
  - preview behavior
- Preserve the current tracker behavior and current visual style that the user is already satisfied with.
- Ensure the settings panel copy describes the tracker directly without external references.

`Bloodlust Sound`

- Keep the same shell styling and grouped control layout.
- Avoid placeholder-looking presentation even if the module remains smaller than the tracker section.

**Minimap Behavior**

- The minimap icon can be shown or hidden from settings.
- The icon can be repositioned around the minimap through an explicit interaction path, not by relying on a fixed corner anchor.
- Position is saved in the addon database.
- A reset control restores the default minimap icon placement.
- Tooltip and label text should match the addon tone: concise and clean.

**Interaction Behavior**

- The selected section remains visually obvious.
- Controls align to a consistent content width and spacing rhythm.
- Long sections scroll instead of overflowing or forcing fragile anchor chains.
- Edit mode state changes must update button labels and enabled states reliably.
- Closing settings must still clean up temporary edit mode state correctly.
- Re-rendering a section must not duplicate controls or leave stale widgets behind.

**Implementation Shape**

- Keep the work inside the existing native frame system.
- Split `Settings.lua` responsibilities into smaller local building blocks:
  - shell/frame creation
  - theme tokens and shared styling
  - reusable controls
  - section rendering
- If the split fits best as helper locals inside `Settings.lua`, that is acceptable for the first pass.
- If the file remains too tangled, extract focused helpers into adjacent files only where that materially improves readability and maintenance.
- Module files should describe their settings content, not restyle common controls individually.

**Refactor Requirements**

- Remove fragile “stack by hand forever” anchoring where a small change can break the full panel.
- Introduce reusable helpers for section blocks, spacing, and common row patterns.
- Centralize colors, sizes, and repeated style values.
- Keep the result easy to extend for future modules without restyling each new control from scratch.

**Data Flow**

- Existing addon DB values remain the source of truth.
- Settings controls write back through the existing addon mutation flow where possible.
- Minimap position data is added to saved settings and read during icon creation/update.
- Rendering a section reads the current DB state and rebuilds only the visible content region.

**Error Handling and Stability**

- Missing or partial saved settings must fall back to safe defaults.
- Minimap controls must no-op safely if the minimap button has not been created yet.
- Reset actions must always leave the UI in a coherent visible state.
- UI rebuilds must not depend on accidental child ordering or hidden stale state.

**Testing**

- Extend static tests to lock the presence of:
  - scrollable settings content
  - minimap positioning controls
  - updated concise copy
  - section grouping/navigation structure
- Extend support tests around saved minimap visibility/position behavior.
- In-game validation must confirm:
  - navigation feels stable and selected state is obvious
  - no clipping or overlap in current sections
  - minimap icon can be moved and reset correctly
  - edit mode still toggles cleanly from the settings shell
  - tracker and bloodlust sections inherit the same shell quality

**Success Criteria**

- The settings window feels materially more professional than the current version.
- The addon copy is concise and has some identity without becoming loud.
- The shell can accept more settings without a layout rewrite.
- The minimap icon is fully manageable from the UI.
- The refactor leaves the settings code easier to maintain than the current single-file mixed approach.
