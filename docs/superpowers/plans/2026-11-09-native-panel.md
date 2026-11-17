# Native Panel Implementation Plan

> **For agentic workers:** Execute inline using executing-plans; request one fresh code review at the end.

**Goal:** Implement the approved compact native menu bar panel without losing operations.

**Architecture:** SwiftUI arranges a single material surface; AppKit owns native popup
controls and menu tracking. Pure display presentation resolves target identity and
constructs options; existing operation and DDC engines remain intact.

**Tech Stack:** Swift, SwiftUI, AppKit, Swift Testing.

**Spec:** ../specs/2026-11-09-native-panel-design.md

## Global Constraints

- macOS 14+, no third-party UI dependencies.
- Fixed window/root size; no visible window frame writes.
- Preserve all existing functions and current uncommitted user work.
- Tests run through `bash Support/run-tests.sh`.

## Review Focus

- Disconnect/same-name displays: a valid target remains unambiguous.
- Stale menus: replaced targets/configurations cannot execute old closures.
- Single/empty modes: retain current value without an unusable picker.
- Many sliders/small displays: bounded viewport, no window resizing.
- Presets: all entries, matching checkmarks and shortcut hints remain available.

## Task 1: Display context and hierarchical native menus

Files: new `PanelDisplayContext.swift`; modify `ParameterMenu.swift`; add behavior
tests in `PanelDisplayContextTests.swift` and `ParameterMenuTests.swift`.

- [x] Add failing tests for target fallback, duplicate names, grouped commands,
      deferred submenu actions, disabled entries and identity-based invalidation.
- [x] Run tests and confirm missing behavior.
- [x] Implement `PanelDisplayContext` and recursive `ParameterMenuOption` entries,
      native popup presentation and cancellation signatures.
- [x] Run the full test suite.

## Task 2: Compact panel and settings navigation

Files: `PanelView.swift`, `PanelGlass.swift`, `Localization.swift`,
`PanelController.swift`, `SettingsView.swift`, `DockPolicyManager.swift`.

- [x] Replace cards/grid with native selectors, sliders, display options,
      complete presets menu, Settings and More.
- [x] Bound internal scrolling explicitly using content measurement and available
      screen height; preserve fixed host dimensions and click-hit geometry.
- [x] Localize new labels; route Manage Presets directly to the presets tab.
- [x] Build and run the full suite; package without launching or installing.
- [x] Request independent review, address material findings and verify again.

## Execution record

- Baseline: 61 tests passed.
- Work in place on existing `codex/glass-panel-spaces` branch: the approved design
  builds on substantial uncommitted changes; moving checkouts would omit them.
- Do not auto-commit or stage the mixed worktree. Final diff remains reviewable.
- Task 1: complete — 69 tests in 12 suites passed, including nested menu dispatch,
  cancelled pending actions, same-label target replacement, accessible single-item
  command menus, selection fallback and viewport bounds.
- Task 2: complete — release App + DMG generated; strict codesign verification
  passed with MoniSwitch Dev certificate requirement, min OS 14.0, SDK 27.2.
- Independent review: no Critical/Important findings. Corrected the minor theme
  footnote mismatch to describe panel material instead of Liquid Glass.
- Desktop verification needs user consent because the activity probe reports
  active computer use. No real parameter operations or desktop actions performed.
- Desktop verification follow-up: user consent received. The desktop controller
  timed out connecting to MoniSwitch by both bundle path and bundle ID. Finder
  access worked, but did not expose the MoniSwitch status item. Its documented
  optional launch API was unavailable. Stopped without quitting/restarting the
  running app or changing display parameters; real panel/menu validation remains
  pending a manual relaunch. This is an automation limitation, not evidence of an
  application failure.
