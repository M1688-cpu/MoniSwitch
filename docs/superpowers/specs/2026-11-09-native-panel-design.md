# Native menu bar panel

Approved in chat on 2026-11-09 with “开始”.

Use one system material panel. Show all controllable external brightness sliders,
a named target-display picker, a resolution picker, display options, a preset menu,
Settings and More. Display options contain refresh rates, left/right placement,
primary-display command, mirror-to-main and extend. More contains auto-arrange,
refresh and quit. Preserve every existing option, HiDPI variants, preset checks,
shortcut hints, settings, brightness-key semantics and HUD.

Keep the existing NSStatusItem/NSPanel and fixed window/root dimensions. Content
height only determines outside-click dismissal. Scroll excess content within an
explicit bounded viewport. Menu tracking must end before running an operation;
changes of target, options, busy state or display configuration invalidate it.

Use native controls without nested glass cards. Retain subtle theme tint on the
single backdrop; respect system appearance and reduced transparency. macOS 14+,
no UI dependencies. Do not add unsupported display capabilities.

Implementation calls: target defaults to main, persists while available, falls
back after disconnect; duplicate names get an ordinal sorted by persistent ID.
Detailed-info preference controls the target summary, never hides mode identity.
Manage Presets opens the existing presets settings tab directly.

Desktop interaction and screenshot verification require a separate agreed testing
window; compilation, unit tests and packaging may run without taking the desktop.
