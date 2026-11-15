# Notchwheel

macOS menu bar app: hold ⌥ while dragging image files, drop onto a radial wheel to compress or
convert them; a notch-style pill shows progress and the result.

**Read `PRD.md` first.** It is the source of truth for scope (P0 / P1 / P2), acceptance criteria,
technical approach and the milestone plan. Don't build P1/P2 items unless asked.

## Project layout

- `Notchwheel.xcodeproj` — Xcode 27 project (readable JSON-style `project.xcproj`). Scheme: `Notchwheel`.
- `Notchwheel/` — app sources (`NotchwheelApp.swift` is the entry point).
- `NotchwheelTests/` — Swift Testing unit tests. `NotchwheelUITests/` — UI tests.
- Build from the terminal: `xcodebuild -project Notchwheel.xcodeproj -scheme Notchwheel -destination 'platform=macOS' build`
- Deployment target is macOS 26.6 (the user's Mac), not 14 as the PRD says; fine for a single-user app.
- The user is new to Xcode: explain where changes live and how to test them in Xcode (⌘R run, ⌘. stop, ⌘U tests).

## Working rules

- Native Swift + SwiftUI, macOS 14+, Apple silicon. No third-party dependencies (ImageIO, AppKit).
- Originals are never modified or overwritten (PRD P0-5).
- One milestone per session; each ends with something testable by hand. Milestone 1 (the drag
  gesture spike) is the gate: if a mid-drag panel can't receive Finder's drop, stop and revisit
  the design before building anything else.
- Claude can't see the screen: after each milestone the user describes the manual test result.
- Keep actions behind the `FileAction` protocol so new engines slot into the wheel without UI changes.

## Status

- [x] Milestone 1: spike the gesture — drop from a mid-drag panel works; no permissions needed (polling, see `DragWatcher.swift`)
- [x] Milestone 2: wheel UI — five segments, hover highlight, centre-hole/outside cancel; hit-test tests in `NotchwheelTests`
- [x] Milestone 3: image engine — `FileAction` + `ImageEngine` (ImageIO), `BatchRunner`; tests in `ImageEngineTests`; results shown in the menu bar menu until the pill exists
- [ ] Milestone 4: notch pill
- [ ] Milestone 5: polish and package
