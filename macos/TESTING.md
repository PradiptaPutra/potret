# Testing Potret (native)

Run everything with `./scripts/test.sh`. Do not call `swift test` directly — it will fail, for
reasons worth knowing before you spend an hour on them.

## Why the wrapper exists

This project is built with the **Command Line Tools only — Xcode is not installed.** That removes
more than `xcodebuild`:

| Missing | Consequence |
|---|---|
| `XCTest.framework` | **Not in the CLT SDK at all.** No `XCTestCase`, no `XCTAssert`, and no XCUITest. UI behaviour is verified by hand against the checklist below, plus golden images. |
| `actool` | No asset catalogs. The bundle uses a loose `AppIcon.icns` (`scripts/make-icns.sh`). |
| `ibtool` | No xib/storyboard. Every view is built in code. |
| `xcbuild` | `swift build --arch arm64 --arch x86_64` fails — two `--arch` flags switch SwiftPM to the Xcode build system. `scripts/build-app.sh` builds each `--triple` separately and `lipo`s them instead. |
| SwiftUI previews | Replaced by `PotretMockup`, which renders views offscreen to PNG. |

So the suite is **swift-testing** — `import Testing`, `@Test`, `#expect` — and it needs three
flags that SwiftPM does not supply on its own:

- `-F /Library/Developer/CommandLineTools/Library/Developer/Frameworks` — where
  `Testing.framework` actually lives.
- `-Xfrontend -disable-cross-import-overlays` — importing `Testing` and `Foundation` in the same
  file auto-loads the cross-import overlay `_Testing_Foundation`. CLT ships that framework's
  dylib but **not** its `.swiftmodule`, so the load fails with `no such module
  '_Testing_Foundation'`. Nothing here needs the overlay.
- `-rpath` to the same directory — otherwise the test bundle links `Testing` at `@rpath` and dyld
  cannot find it at run time.

## What is covered by tests

`PotretCore` imports Foundation and CoreGraphics only — no AppKit, no SwiftUI — so it runs
headless with no display, no run loop and no TCC grant. That is where the coverage lives:

- filename templating (`{date}` `{time}` `{unix}` `{seq}`, illegal-character sanitising, collision
  suffixes)
- config round-trip, and migration from a real Tauri `config.json` fixture
- `KeyCombo` and the reserved-shortcut table
- history store and retention policy
- **`CoordinateSpace`** — NSScreen ↔ ScreenCaptureKit ↔ pixel conversions. The highest-value test
  file in the project; multi-display geometry is where this app is most likely to be wrong.
- `DocumentTransform` round-trips at 1×, 2× and arbitrary zoom
- hit-testing and handle geometry
- `apply → undo == original` as a property over randomised edit sequences

`PotretRender` adds golden-image tests: fixed documents rendered at scale 1 and 2 against
checked-in PNGs, tolerance mean-abs-diff < 2/255. Regenerate with
`POTRET_UPDATE_GOLDENS=1 ./scripts/test.sh`.

Three goldens exist specifically to make previously-shipped bugs unreproducible: text at scale 2,
a rounded-rect shadow at `cornerRadius: 12`, and a pixelate region composited under a vector arrow.

## What must be checked by hand

No UI automation is available, so these are a real checklist, not a formality.

**Permissions**
- [ ] First launch with Screen Recording never granted
- [ ] Denied, then granted, then relaunched
- [ ] Revoked while the app is running
- [ ] Upgrade in place from the Tauri build — **must not re-request Screen Recording**

**Focus and Spaces** (the bug class that produced seven consecutive Tauri releases)
- [ ] Capture while another app is frontmost — Potret must **not** become frontmost
- [ ] Switch Spaces after a capture — must not be yanked back
- [ ] Every overlay over another app's fullscreen window
- [ ] Selector panel torn down by Esc, by app deactivation, and by the watchdog

**Displays**
- [ ] Two displays at different scale factors
- [ ] A display positioned above the main one (negative Y)
- [ ] Arrangement changed mid-drag
- [ ] Region crop lands exactly where the marquee was, on a 2× display

**Selection options bar**
- [ ] Selection survives mouse-up; handles resize from every edge and corner
- [ ] Aspect lock holds the ratio from a corner and from an edge
- [ ] Typed W/H applies on Return, anchored top-left, clamped to the screen
- [ ] A size field takes the keyboard, and Return hands it back so Return captures
- [ ] Freeze holds the screen still, and capturing crops the frozen frame, not a fresh one
- [ ] Self-timer counts down without stealing focus from the thing being captured
- [ ] Record in the bar starts a region recording even when the selector was opened to capture
- [ ] The bar flips above the selection near the screen bottom, and never leaves the screen

**Other**
- [ ] Drag-out to Finder, Slack, Mail, Preview
- [ ] Light/Dark × Increase Contrast × Reduce Motion × a non-blue accent colour
- [ ] Menu bar with Bartender or similar installed
- [ ] Gatekeeper first-open from the DMG

**Recording** (Phase 6)
- [ ] 10-minute recording: no dropped frames, no A/V drift
- [ ] Stop from the HUD, the global hotkey, and the status item
- [ ] Disk full mid-recording
- [ ] Display disconnected mid-recording
- [ ] Pause/resume A/V sync
