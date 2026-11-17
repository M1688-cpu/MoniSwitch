# Panel Motion Implementation Plan

> Execute inline using executing-plans; preserve the existing working tree.

**Goal:** Open the menu bar panel downward from a fixed top edge with subtle scaling and fading in about 0.2 seconds.

**Architecture:** Keep the fixed NSPanel and fixed SwiftUI ideal size. Correct the hosting layer's anchor for flipped coordinates, disable AppKit's additional window animation, and retain layer-only presentation changes.

**Tech Stack:** Swift, AppKit, SwiftUI, Core Animation, Swift Testing.

**Spec:** User-approved brief in this conversation (2026-10-25): subtle top-anchored scale/fade, native macOS feel, reduce-motion support, rapid-toggle safety, source and packaged app.

## Constraints and review focus

- Never resize a visible panel; preserve existing card styles and internal expansion.
- Preserve unrelated uncommitted work; no branch-wide commit.
- Respect flipped hosting coordinates, including after attachment/layout.
- Reopening during dismissal must invalidate the old completion.
- Reduce Motion uses fading without geometric motion.
- Desktop launch/click/capture requires knock-first consent.

## Task 1: Correct and verify presentation

- [x] Extract existing anchor setup unchanged into a production helper; test visual top invariance on a real, unattached NSHostingView (no desktop interaction).
- [x] Observe the regression fail, then correct coordinate direction; recheck normal and flipped hosts.
- [x] Use 0.96 scale, 0.22s opening and 0.16s closing; disable system window animation, honor Reduce Motion, guard interrupted dismissal.
- [x] Run `bash Support/run-tests.sh`, package with `bash Support/build-app.sh`, review only this task's changes.
- [x] Request desktop consent for launch, animation inspection and rapid toggle checks; report actual verification limits.

## Evidence and decisions

- Initial no-window probe: NSHostingView.isFlipped=true; old anchor (0.5,1), scale 0.92 moved visual top down 80pt for a 1000pt host.
- Work directly in the existing checkout because the current app depends on extensive uncommitted v2 changes. Preserve these changes and avoid a commit that would absorb them.

- Regression before fix: flipped hosting top shifted 40pt / 20pt at 0.96 / 0.98 scale; test failed twice. After fix: 59 tests in 10 suites passed, including both hosting orientations.

- Release packaging succeeded with MoniSwitch Dev signing; signature verified. Independent review found no actionable defect.
- User authorized desktop validation. New packaged app launched at the exact Support path. Automation stopped because System Events returned -1719 (accessibility denied) and CUA timed out for the exact app path. No screenshots or recordings obtained. Real-window attachment/layout, rapid reversal and Reduce Motion remain unverified on desktop; no system settings changed.
