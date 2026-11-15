# Notchwheel PRD

Nov 15, 2026 · @Arjun

## Summary

Notchwheel is a macOS menu bar app that compresses and converts images the moment you drag them. Hold ⌥ while dragging any image file and a radial wheel appears under the cursor; drop onto a segment and the processed file lands next to the original. A notch-style pill at the top of the screen shows progress and the result (e.g. "4 files, 18.6 MB → 2.3 MB").

**Problem.** Shrinking or converting an image today means opening Preview, choosing Export, picking a format and quality, then naming and saving. It takes 30 to 60 seconds per batch and breaks focus. HEIC photos from an iPhone are the worst case: many upload forms (uni portals, Xero attachments, some web apps) reject them or choke on 4 to 6 MB files.

**Prior art.** Dropover and Yoink offer drag shelves; NotchNook and NotchDrop put a drop zone in the notch. Dropover has basic image actions but buries them in a menu. None offer a one-gesture radial picker with presets. The bet is that removing the menu step is the whole value.

## Goals

1. Drag to finished file in under 3 seconds for a batch of 10 iPhone photos.
2. Zero false triggers: the wheel never appears on a normal drag without ⌥.
3. Never lose or overwrite an original file.
4. Replace the Preview export workflow entirely within two weeks of daily use.

## Non-goals (v1)

| Out of scope | Why |
| --- | --- |
| PDF merge and compress | Different engine (PDFKit) and merge needs ordering UI; strong v2 candidate |
| Video compress | AVFoundation export is slow and needs progress and cancel handling; doubles scope |
| Zip and unzip | Finder already does this in one right-click |
| Cloud processing or sync | Local ImageIO is fast enough and keeps files private |
| App Store release | Sandboxing blocks writing next to the original without extra permission prompts; ship as a direct-download app |
| Windows or Intel-only Macs | Built for one notched Apple silicon MacBook |

## User stories

One user, moving screenshots, receipts and phone photos into portals, Xero and Slack.

- As the user, I want to hold ⌥ mid-drag and drop a HEIC photo onto "→ JPG" so I can upload it to a portal that rejects HEIC.
- As the user, I want to drop 12 photos onto "Compress" at once so a batch fits under an email or upload size limit.
- As the user, I want the output saved beside the original with a clear suffix so I can find it without a save dialog.
- As the user, I want location metadata stripped on compress so photos I share don't leak where they were taken.
- As the user, I want a clear notch message when a file can't be processed (e.g. a PDF dropped on the wheel) so I'm not left guessing.
- As the user, I want to let go of ⌥ or drop outside the wheel to cancel, so a mistaken trigger costs nothing.

## Requirements

The P0 list is the smallest build that replaces Preview export. Everything else waits until P0 has been used daily for a week.

### P0: must ship

| ID | Requirement | Acceptance criteria |
| --- | --- | --- |
| P0-1 | Wheel appears when ⌥ is held during a file drag | Given a drag of one or more files from Finder or the desktop, when ⌥ is held for 150 ms, the wheel appears centred on the cursor within 100 ms. Without ⌥, nothing appears. |
| P0-2 | Wheel accepts the drop | Dropping on a segment triggers that action. Releasing ⌥ before drop hides the wheel and the drag continues normally. Dropping outside the wheel does nothing. |
| P0-3 | Five segments | Compress, → JPG, → PNG, → HEIC, Resize (longest edge 2048 px). Segment highlights on hover. |
| P0-4 | Image pipeline | Reads HEIC, JPG, PNG, TIFF, WebP, GIF (first frame). Compress = JPG at quality 0.75, longest edge capped at 2560 px, GPS and EXIF stripped. Batch of 10 HEIC photos finishes in under 3 s on Apple silicon. |
| P0-5 | Safe output | New file next to the original, named `photo-compressed.jpg` / `photo.jpg`; if the name exists, append `-2`. Originals are never modified. |
| P0-6 | Notch feedback | Pill at the top centre shows a spinner during work, then "N files, X MB → Y MB" for 3 s. Click reveals outputs in Finder. |
| P0-7 | Unsupported files | Non-image files are skipped; the pill reports "2 skipped (not images)". The app never crashes on bad input. |
| P0-8 | Menu bar presence | Menu bar icon with Quit, Launch at Login and a permissions status line. |

### P1: fast follows

- Settings: trigger key (⌥, ⌃ or ⌘⇧), JPG quality slider, max dimension, keep or strip metadata.
- Drag straight onto the notch pill as an alternative trigger, no key needed.
- Undo last batch from the pill (moves outputs to Bin).
- Target size preset, e.g. "under 1 MB", which searches quality until it fits.

### P2: design for, don't build

- PDF merge and compress, video compress. Keep each action behind a common `FileAction` protocol so new engines slot into the wheel without touching the UI.
- User-defined segments and a second ring for sub-options.

## Technical approach

Native Swift and SwiftUI, macOS 14+, no third-party dependencies. Apple's ImageIO handles every P0 format, so there is no need for ImageMagick or a bundled binary.

1. **Drag detection.** A global `NSEvent` monitor on `leftMouseDragged` checks `NSEvent.modifierFlags` for ⌥ and reads `NSPasteboard(name: .drag)` to confirm the drag carries file URLs.
2. **Wheel.** A borderless, non-activating `NSPanel` at floating level, shown under the cursor and registered as a drag destination for file URLs. SwiftUI draws the segments; hit-testing maps cursor angle to a segment.
3. **Action.** Each segment maps to a `FileAction` (input URLs → output URLs). Work runs on a background task queue, one file per core.
4. **Image engine.** `CGImageSource` to read, `CGImageSourceCreateThumbnailAtIndex` for fast downscaling, `CGImageDestination` to write with quality and metadata options.
5. **Notch pill.** A second panel pinned to the top centre of the built-in display, sized from `NSScreen.auxiliaryTopLeftArea` and `auxiliaryTopRightArea` so it hugs the notch.

## Risks

| Risk | Impact | Mitigation |
| --- | --- | --- |
| A panel appearing mid-drag may not receive the drop from Finder's drag session | Kills the core gesture | Build this first as a throwaway spike (Milestone 1). If it fails, fall back to the notch pill as the drop target. |
| macOS may require Accessibility or Input Monitoring permission for the global monitor | Extra setup friction, possible silent failure | Detect permission state at launch; show status in the menu bar and a one-click link to System Settings. |
| ⌥ already means "copy" in Finder drags | Dropping outside the wheel with ⌥ held makes a copy instead of a move | Acceptable: a copy is non-destructive. Make the trigger key configurable in P1. |
| Notch geometry differs across MacBook models, and external monitors have no notch | Pill misplaced | Fall back to a top-centre pill on screens without a notch. |

## Build plan (Claude Code)

One milestone per Claude Code session, each ending in something you can test by hand. Milestone 1 is the gate: if the drop doesn't land, the design changes before you build anything else.

1. **Spike the gesture.** Bare menu bar app. Hold ⌥ mid-drag, a plain circle appears, dropping on it logs the file paths. Gate: works from Finder windows and the desktop.
2. **Wheel UI.** Five segments, hover highlight, cancel on ⌥ release or drop outside. Gate: P0-1 to P0-3 pass.
3. **Image engine.** `FileAction` protocol plus the five actions, with unit tests against sample HEIC, PNG and WebP files. Gate: P0-4, P0-5 and P0-7 pass.
4. **Notch pill.** Progress, result line, click to reveal. Gate: P0-6 passes.
5. **Polish and package.** Launch at Login, permissions status, signed `.app` in `/Applications`. Gate: one week of daily use with no workaround needed.

Practical setup: create the Xcode project yourself first (App template, SwiftUI, set `LSUIElement` to hide the Dock icon), then point Claude Code at it. Save this PRD as `PRD.md` in the repo and reference it from `CLAUDE.md` so each session starts with the same context. Claude Code can't see your screen, so after each milestone describe exactly what happened during your manual test.

## Success metrics

The app keeps a local log (date, action, file count, MB in, MB out). Review it after two weeks.

| Metric | Target |
| --- | --- |
| Uses per week | 10+ (the threshold for daily habit) |
| Times Preview export was used instead | 0 in week two |
| Accidental wheel triggers | Under 1 per week |
| Median time, drop to finished output (10 photos) | Under 3 s |
| Average size reduction on Compress | 70%+ on iPhone HEIC |

## Open questions

- [ ] Does a panel shown mid-drag reliably receive Finder's drop? Blocking; answered by Milestone 1.
- [ ] Which permission does the global drag monitor need on your macOS version? Blocking; answered by Milestone 1.
- [ ] Can ImageIO write WebP on macOS 14? If yes, add a "→ WebP" segment in P1.
- [ ] Is 2048 px the right Resize preset, or do your uploads need something smaller?
