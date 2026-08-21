# Dock Stick Forever

Pin the macOS Dock to one display. It stops jumping when your pointer touches
the bottom edge of another screen.

Works on macOS Sequoia and Tahoe, where the well-known `autohide-delay` trick
no longer does anything.

## The problem

On a multi-display Mac, macOS hands the Dock to whichever screen your pointer
presses against the bottom edge of. There is no setting to turn this off.

For a decade the community workaround was:

```sh
defaults write com.apple.dock autohide-delay -float 999999; killall Dock
```

The idea was to stretch the delay before the Dock agrees to move to something
effectively infinite.

**This stopped working in macOS Sequoia.** Apple changed multi-display Dock
behaviour and [told developers it was expected behaviour][forum], not a bug.
The preference is still read by the Dock — it simply no longer influences
display switching. You can verify this on your own machine: write the value,
confirm the Dock process started *after* the plist was written, and watch it
jump anyway.

No `defaults` key replaces it. If you find a repo advertising a "one-command
fix", check its install script — it is almost certainly writing `autohide-delay`
and a LaunchAgent to keep it there, which is the approach that already broke.

[forum]: https://developer.apple.com/forums/thread/764007

## How this works

macOS decides where the Dock goes from pointer position. We cannot intervene in
that decision, but we can intervene in its input.

Dock Stick Forever installs a `CGEventTap` at the head of the session event
queue. For every pointer sample:

1. Find the display containing the pointer.
2. If it is the anchored display, pass the event through untouched.
3. Otherwise, if the pointer is inside a thin band along that display's bottom
   edge, rewrite the event location to sit on the band's upper boundary.

The bottom edge of every non-anchored display becomes permanently unreachable,
so the Dock's trigger condition never becomes true. Horizontal movement is
unaffected — only the vertical coordinate is constrained, and only inside that
band.

No `killall Dock`. No flicker. Nothing written to `com.apple.dock`.

## Trade-offs

Worth knowing before you install:

- Requires **Accessibility** permission. Every event tap does.
- Runs a background process (~170 KB, menu bar only, no window).
- The bottom few points of non-anchored displays become unclickable. At the
  4 pt default this is imperceptible in practice, but if it ever gets in your
  way, drop it to 2 pt from the menu.

## Install

### From source

```sh
git clone https://github.com/binhsonnguyen/dock-stick-forever.git
cd dock-stick-forever
./build-app.sh
./install-app.sh
open ~/Applications/"Dock Stick Forever.app"
```

### From a release

Download the zip from [Releases](../../releases), unzip, and move
`Dock Stick Forever.app` into `~/Applications`.

The release build is **ad-hoc signed and not notarized** — I do not have a paid
Apple Developer account. macOS will refuse to open it on first launch. To get
past Gatekeeper:

```sh
xattr -dr com.apple.quarantine ~/Applications/"Dock Stick Forever.app"
```

If that feels like too much trust to extend to a stranger's binary, build from
source instead. It takes about five seconds and needs nothing but Xcode command
line tools.

On first launch the app asks for Accessibility access. Grant it in
System Settings → Privacy & Security → Accessibility. The app polls for the
change, so there is no need to relaunch.

## Menu

| Item | Meaning |
|---|---|
| Enable | Toggle the guard without quitting |
| Anchor display | Which display keeps the Dock. Defaults to the main display |
| Guard band | 2/4/8/16 pt. Raise it if the Dock still slips through, lower it if it interferes |
| Strong mode (warp pointer) | Also force the pointer position instead of only rewriting the event. Only needed if the default is not enough — it usually is |
| Open at login | Registered through `SMAppService` |

*(Menu labels ship in Vietnamese.)*

## Architecture

```
Sources/
  DockStickCore/           Pure geometry, no AppKit -- testable without a mouse
    DockGuard.swift
  DockStickApp/
    main.swift             Entry point
    AppDelegate.swift      Menu bar UI
    PointerGuardTap.swift  CGEventTap plumbing and lifecycle
    DisplayInventory.swift Display enumeration, UUID identity
    Settings.swift         UserDefaults
Tests/
  DockStickCoreTests/      9 geometry tests
```

Splitting out `DockStickCore` is deliberate. The easiest thing to get wrong
here is the coordinate system: CoreGraphics event coordinates put the origin at
the **top-left** of the main display with `+Y` pointing **down**, which is
upside down relative to AppKit's `NSScreen`. Keeping that logic in pure
functions means it can be verified without plugging in a monitor or moving a
mouse.

```sh
swift test
```

## Implementation notes

Things that cost me time, in case you are building something similar:

- Displays are identified by **UUID**, not `CGDirectDisplayID`. IDs are
  reassigned across sleep, cable swaps and reboots, so an anchor stored by ID
  will silently start guarding the wrong panel.
- Unplugging the anchored display falls back to the main display. Without that
  fallback every display would be guarded and the pointer would be locked out
  of every bottom edge at once.
- With a single display the guard disables itself — there is nothing to fight
  over.
- The system disables an event tap whose callback blocks for too long
  (`.tapDisabledByTimeout`) or when Accessibility access is revoked
  (`.tapDisabledByUserInput`). The callback must catch both and re-arm, or the
  app dies quietly.
- `CGDisplayRemoveReconfigurationCallback` needs the *same* function pointer
  that was registered. Two identical-looking closure literals are two different
  pointers, and the unregister silently does nothing.
- Under Swift 6 strict concurrency `CGEvent` is not `Sendable`. Pass only
  `Sendable` values (a `CGPoint`) across the actor boundary and apply the
  result to the event outside it.
- Accessibility approval is keyed to the code signature. An ad-hoc signed build
  gets a new cdhash every time, so re-running `build-app.sh` means granting
  permission again.

## Alternatives

- **Turn off "Displays have separate Spaces"** (System Settings → Desktop &
  Dock → Mission Control). Apple's only official answer. The Dock stays on the
  main display, but you lose per-display menu bars and per-display fullscreen,
  and it needs a logout.
- **Move the Dock to the left or right.** It anchors to the outer edge of your
  display arrangement and has nowhere to jump. Cheapest fix if you can live
  with a vertical Dock.
- **[bwya77/DockAnchor](https://github.com/bwya77/DockAnchor)** — same event tap
  technique, more features (profiles, a live display map). Use it if you would
  rather not maintain your own.

## License

MIT. See [LICENSE](LICENSE).
