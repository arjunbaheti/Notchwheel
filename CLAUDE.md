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

- Signing (19 Nov 2026): app targets sign with a self-made certificate "Arjun Local Code Signing" in the user's
  login keychain (trusted for code signing only; created at the user's choice instead of an Apple ID). It gives a
  stable designated requirement, so macOS keeps Calendar/Automation permissions across rebuilds; ad-hoc signing
  made it re-ask after every build. If that identity is missing, builds fail: recreate it or switch the app target
  back to CODE_SIGN_STYLE Automatic. Test targets stay ad-hoc.

## Status

- [x] Milestone 1: spike the gesture — drop from a mid-drag panel works; no permissions needed (polling, see `DragWatcher.swift`)
- [x] Milestone 2: wheel UI — five segments, hover highlight, centre-hole/outside cancel; hit-test tests in `NotchwheelTests`
- [x] Milestone 3: image engine — `FileAction` + `ImageEngine` (ImageIO), `BatchRunner`; tests in `ImageEngineTests`; results shown in the menu bar menu until the pill exists
- [x] Milestone 4: notch pill — `NotchPill.swift` (panel above the menu bar, centred on the notch via `auxiliaryTopLeft/RightArea`; top-centre fallback); geometry tests in `NotchPillTests`
- Arjun's Notch handoff (19 Nov 2026): `NotchSignal` in `NotchPill.swift` posts distributed notifications
  `com.arjunbaheti.Notchwheel.pillWillShow` / `pillDidHide` so Arjun's Notch (~/Desktop/arjuns-notch) steps
  aside. Keep these names stable; Arjun's Notch listens for them.
- [~] Milestone 5: polish and package — built 18 Nov 2026, gate (one week of daily use) pending. Launch at Login
  (`LoginItem.swift`, SMAppService; only enabled when running from /Applications), "no permissions needed"
  status line, local usage CSV (`UsageLog.swift`, ~/Library/Application Support/Notchwheel/usage.csv; tests in
  `UsageLogTests`). Template UI tests removed (XCTest can't terminate an LSUIElement app).
  Installed at /Applications/Notchwheel.app, ad-hoc signed (no Apple developer certificate on this Mac).
  To reinstall after changes: quit Notchwheel, then
  `xcodebuild -project Notchwheel.xcodeproj -scheme Notchwheel -configuration Release -derivedDataPath /tmp/nw-release build`
  and `ditto /tmp/nw-release/Build/Products/Release/Notchwheel.app /Applications/Notchwheel.app`.
  Don't run the Xcode build and the installed app at the same time: two wheels stack up.
  The Xcode Debug build also shows up in Spotlight/Apps as a second "Notchwheel"; suggested fix is adding
  ~/Library/Developer to Spotlight Search Privacy. User confirmed the installed app works (19 Nov).
- [x] Extra (user request, 18 Nov 2026; PDF was P2 in the PRD): sixth "PDF" segment. `PDFMaker.swift` combines
  all dropped images into one PDF (filename order, A4 pages, landscape for landscape images, images capped at
  2480 px and embedded as JPEG 0.8). Many-in/one-out, so it bypasses `FileAction`; `WheelSegment.run(on:)`
  picks the engine and `WheelSegment.action` is nil for `.toPDF`. Tests in `PDFMakerTests`. Confirmed working by the user (18 Nov).

## Wheel polish after Milestone 4 (confirmed working by the user, 18 Nov 2026)

- Sticky hover (hysteresis) to stop the highlight twitching on segment boundaries: `WheelGeometry.segment(at:keeping:)`.
- Liquid Glass look on the wheel (`glassEffect` in `WheelView.swift`).
- After adding glass, drops/highlighting stopped working entirely. Suspected cause: glass views
  intercepting the drag. Fix applied: `WheelDropTarget` is now the panel's root view with a
  catch-all `hitTest`, SwiftUI hosted inside it. First thing next session: user tests ⌘R; if
  highlighting still fails, remove `glassEffect` to confirm the cause.
- 18 Nov: hover highlight changed back to a solid accent fill over glass (glass tint alone looked muted).
- 18 Nov test: still no highlight, and dropping duplicated the file. Diagnosis: the drop fell
  through the panel to Finder (⌥-drop in Finder = copy). Glass is composited outside the window's
  backing store, so the window server saw transparent pixels and routed the drag past us. (Also
  the "catch-all hitTest" above had never actually been written.) Fix: `ignoresMouseEvents = false`
  on the panel, `hitTest` override on `WheelDropTarget`, and a 1%-alpha disc drawn under the wheel.
  Confirmed: highlight and drops work.
- Watch for stale debug instances: an old build left running put a second drop panel on top
  (`pgrep -lf Notchwheel.app`).
