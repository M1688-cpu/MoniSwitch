# Glass panel and active Space implementation plan

> Execute inline using executing-plans. The user approved the brief in chat on 2026-10-26; no further design approval is needed.

**Goal:** Open the panel on the clicked desktop and replace its internal presentation with native glass controls.

**Approved spec:** Keep the brightness, displays, parameters, presets and toolbar sections. Add one overall glass backplate. Themes provide a subtle glass tint. Display selectors are equal-size icon buttons with name tooltips. Parameter rows are equal-height glass controls with native scrolling selection menus. Primary/mirror/extend actions are equal-size icon-only buttons with tooltips. Remove custom animations, retain native control feedback.

**Architecture:** Preserve the fixed-size NSPanel/NSHostingView safety boundary. Move the window to the active Space when ordered front, hide on Space changes, and distinguish visibility from active-Space presence. Use SwiftUI glassEffect on macOS 26+, system material on macOS 14/15, and an AppKit NSMenu bridge for parameter choices. Native menu tracking must suppress the panel's outside-click dismissal.

**Constraints:** Swift 5 mode / macOS 14 minimum; no DDC or displayplacer behavior changes; no visible-window resizing; no desktop automation without the user's consent; preserve existing unrelated files.

## Tasks

- [x] 1. Replace obsolete animation-anchor tests with active-Space toggle and panel-window policy tests. Implement the window policy and instant show/hide; close on Space changes.
- [x] 2. Add native parameter menu tests for option labels/checkmarks, disabled state and action dispatch. Implement the menu bridge, including tracking lifetime and cancellation.
- [x] 3. Implement shared native glass surfaces and equal-size buttons. Replace display diagrams and inline option expansion. Keep section order and existing operation callbacks. Remove retired animation-only components.
- [x] 4. Update the theme explanation and project architecture notes. Run the full test suite and signed release packaging; independently review the diff.
- [ ] 5. Request desktop verification only after the app is ready: active Space, scrolling/checkmarks, light/dark glass, tooltips, dismissal and rapid toggles. Report any unverified conditions explicitly.

## Review focus

- Visible but off-Space windows must open, not toggle closed.
- Native menu choices outside the panel rectangle must remain clickable.
- HiDPI and low-resolution variants must not receive incorrect current-item checks.
- All controls must respect busy/disabled state, including the native menu bridge and auto-arrange.
- Parameter removal must remove hit targets; window dimensions must remain fixed across display switches.

## Evidence / rulings

- Initial checkout: main, tracked files clean; unrelated untracked user artifacts present. Work continues on codex/glass-panel-spaces in the existing checkout to preserve its bundled displayplacer and local build environment.
- Existing collectionBehavior already includes canJoinAllSpaces; static inspection cannot establish a WindowServer-level root cause. Automated policy tests are not a substitute for a real two-Space reproduction. This remains a required desktop verification item.
- Existing user approval covers implementation and packaging. Desktop takeover is a separate project requirement.

- Native tooltips replace the entire custom floating-tooltip/animation subsystem; its five obsolete geometry tests were removed. Parameter menu options and Space policy have focused replacement coverage.
- Review: single-display selection now toggles normally; menu controllers cancel on disabled/changed/dismantled triggers and revalidate before execution; all glass shares a container.
- Unit test harness correction: NSMenu target/action dispatch requires NSApplication.shared even without presenting a window. The production app already has it.

- Follow-up: user reported the first live version still looked frosted. Replaced stacked regular glass with clear glass, separated the backdrop/card/control sampling layers, retained a neutral readability scrim and reduced-transparency fallback. No custom highlights or animations were added.
- Key-window regression: observed panel.canBecomeKey fail before the fix; now the nonactivating panel supports native key-window controls and is made key on presentation. It cannot become the main window.
- Verification: 59 tests passed (10 suites); signed release and DMG rebuilt with SDK 27.0; codesign --verify --strict passed. Latest app successfully launched from Support/MoniSwitch.app.
- Desktop automation blocker: CUA can read the settings window, but repeatedly times out on the accessory app and continues to capture Settings even when the user opens the panel. Process sampling showed a healthy idle main run loop, not an app hang. No actual panel screenshot, native scrolling interaction, or two-Space acceptance proof has been captured. Keep task 5 pending; do not claim the reported Space issue or final visual appearance verified.
- Existing theme blueGray was not changed. No display mode or brightness was changed during UI verification.
