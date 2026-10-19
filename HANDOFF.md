# Handoff (2026-10-19, paused here)

Where things stand, what's left, and how to set up a new machine.

## State

| Repo (your forks) | Branch | Commit | Pushed? | What |
|---|---|---|---|---|
| `Delici0u-s/saber` | `main` (only branch; `personal` deleted 2026-10-19) | see `git log` | yes | Fork features + lock on library `8808f44` |
| `Delici0u-s/perfect-freehand-dart` | `personal` | `8808f44` | yes | PR + all tap fixes |
| same | `fix/stationary-dots` | `92c70b3` | yes | PR [#27](https://github.com/steveruizok/perfect-freehand-dart/pull/27) |

Saber gets `perfect_freehand` from the fork's **`personal`** branch via `dependency_overrides`
in `pubspec.yaml`; `pubspec.lock` pins the commit (`flutter pub upgrade perfect_freehand` bumps it).
This does **not** switch to upstream by itself: see "When the PR is released" below.

### PR #27 commits

| Commit | What |
|---|---|
| `79a500a` | Dots for stationary points with varying pressure (original PR) |
| `640c910` | Test: stationary points golden |
| `8e380a6` | A tap's dot sized by the highest pressure; points within `options.size` of the first count as one tap (squash of `bf82a2f`, `492156a`, `d6ef51f` on `personal`) |
| `92c70b3` | **Lone point drawn as a round dot** (= `8808f44` on `personal`) |

After `92c70b3`, `lib/` and `test/` on `fix/stationary-dots` are identical to `personal`.

What the bugs were:
- **Pressure**: a real tap drifts by a fraction of a pixel. Then the middle points were skipped
  and the dot used the *last* (lift-off, lightest) point's pressure. Verified on the tablet.
- **Stretched dots** (seen on the laptop with a thin pen): `getStrokePoints` added a helper
  point 1pt right and down from a lone point (upstream behaviour, also in the JS library), so every
  dot was a tiny diagonal stroke, √2 ≈ 1.4pt longer along ↘. Fix: drop the helper point;
  `getStrokeOutlinePoints` already draws a lone point as a round dot. Goldens changed (dots only):
  `one_point`, `two_equal_points`, `stationary_points`, `short_strokes`. Verified in the app on
  the laptop (2026-10-19).

All checks pass on both branches: 64 tests, `dart format`.

## What's left

### 1. Respond to review on PR #27, if any

Make changes on `personal` first (that's what Saber uses), then bring them to
`fix/stationary-dots` (cherry-pick, or squash if the reviewer asks for fewer commits).

### 2. When the PR is released

The override is manual: pub can't fall back to upstream by itself, and a merge isn't enough
(the normal dependency comes from pub.dev). Once a `perfect_freehand` release on pub.dev has
the fixes: delete the `perfect_freehand` block under `dependency_overrides` in `pubspec.yaml`,
raise `perfect_freehand: ^2.5.1` to that release, `flutter pub get`, test, commit.

Keep the override on `ref: personal` until then (not `fix/stationary-dots`): you control
`personal`, while the PR branch may be rebased during review.

### 3. Line styles for pen and pencil (done, `6005f64a`)

Solid, dashed, dotted and dash-dot, picked in the pen tab (fountain and ballpoint pen) and the
pencil tab; each pen remembers its own (`lastFountainPenLineStyle` etc.). The pattern lives in
`LineStyle` (`lib/data/tools/line_style.dart`), in multiples of the stroke size. A stroke saves its
style as `ls` (left out for solid), so other Saber versions draw these strokes solid. A styled stroke
is drawn as one outline per dash or dot (`Stroke.splitIntoPieces`), also in PDF exports.
Limits: shapes (hold to shape, shape pen) and the highlighter stay solid; a straight line from hold
to shape keeps its style.
Pressure is simulated along the whole stroke before it's cut into dashes, so dashes don't change
width when the stroke is finished. The area eraser cuts at its edge and keeps each part's place in
the pattern (`lo`, `Stroke.lineStyleOffset`). Tested on the laptop; not yet on the tablet.

### 4. Ruler (done, `06ddf45b`, `25f0d7fa`)

A ruler, try square or set square (Geodreieck) over the canvas (`Ruler`, `RulerOutline` and
`RulerOverlay` in `lib/components/canvas/ruler.dart`; bar in `toolbar/ruler_modal.dart`). It lives
on the screen (`CanvasGestureDetector`), so it stays put while scrolling and isn't saved or exported.
- **Toolbar:** the ruler button shows it and opens a bar: shape, *Mark spacing* (mm between marks,
  `rulerMarkSpacingMm`) and a hide button. Tapping the button again closes or reopens the bar.
- **Move and rotate:** drag the body; drag the ring in its middle to rotate (snaps to multiples of
  15° within 2°, angle shown in the ring); two fingers, a trackpad or the mouse wheel also rotate.
- **Drawing along it:** a pen stroke (any `Pen`) started within the snap distance of a side, on
  either side of it, has every point moved onto that side, half the stroke's width outside it, and
  stops at the side's corners (`EditorState._alongRuler`, `RulerEdge.project`). Pointers in that
  band pass through to the canvas. Snap distance is the *Ruler snap distance* setting
  (`rulerSnapDistance`, 8–32 px); the ruler is a 48 px grab area plus a snap band on each side.
- **Sizes:** the ruler reaches past the screen; the try square and set square scale with the
  window's shorter side (`RulerOutline._bladeOfScreen`, `_setSquareOfScreen`), never smaller than
  the ring needs.
- **Marks:** millimetres on the page as the *Real size paper* setting defines them
  (`ScreenDensity.logicalPixelsPerMm × zoom / realSizeScale`), so real mm at real size zoom. Every
  5th and 10th mark longer, labels in cm; marks and labels are thinned out when they'd crowd, and
  labels that would overlap the ring, a side, the protractor or another scale are left out.

### 5. Test on the devices (yours)

- **Sync flicker** (`6d6d1e7`): tested on the laptop while watching the server, except the last
  change: images to load before a reload are now picked by which pages are on screen. Reinstall
  (`scripts/dev.sh linux install`) and check a reload of a note with images doesn't blink.
- **Line styles and area eraser on the tablet** (`6005f64a`): draw dashed lines with the pen
  (real pressure, unlike the laptop's mouse) and erase across them.
- **Ruler** (`06ddf45b`, `25f0d7fa`): on the laptop and the tablet, each shape: move, rotate (ring,
  two fingers, mouse wheel), draw along every side, change the mark spacing and the snap distance,
  and at *Real size* zoom hold a real ruler to the screen to check the marks. Labels were only
  checked in tests (with a placeholder font), so look at how they fit with the real font.
- **Strokes with corners when zoomed out:** also in upstream Saber. Drawing in full detail down to
  0.5x zoom (`3e39cc4`) didn't make them look smoother on the laptop and was reverted (`1690a0c`),
  so the cause is elsewhere (maybe the mouse's coarse input). Check on the tablet with the pen.
- **Tablet:** still on an older build. `scripts/dev.sh android install` brings the *Real size paper*
  setting and the flicker fix.

### Housekeeping

- Saber has only `main` now (the README says the fork is personal and unmaintained). Note that
  `personal` in the library rows above means the **perfect-freehand-dart** branch, which stays.

### Gotchas

- `flutter test`/`flutter analyze` in the library add a `build/**` exclude to
  `analysis_options.yaml`: undo with `git checkout analysis_options.yaml` before committing.
- `flutter test --update-goldens` rewrites **every** golden in the file, even passing ones.
  Restore the unchanged ones with `git checkout` and commit only the ones that really changed.
- `dart format --set-exit-if-changed` also rewrites files; use `--output=none` to only check.
- **Linux build on this PC** needed: `sudo dnf install webkit2gtk4.1-devel libsoup3-devel
  libsecret-devel jsoncpp-devel libunwind-devel` (done). If a build failed while configuring,
  CMake caches `/usr/local` as the install prefix and the next build fails with "Permission
  denied" copying to `/usr/local/saber`: `rm build/linux/x64/release/CMakeCache.txt` and rebuild
  (never use `sudo`). The "install" is only Flutter copying the app into `build/…/bundle`.
- **Personalized Linux install** (`scripts/dev.sh linux install`): app id
  `com.adilhanney.saber.personalized` (set via `SABER_APPLICATION_ID` in `linux/CMakeLists.txt`),
  files in `~/.local/lib/<id>`, launcher `~/.local/bin/saber-personalized`, desktop entry and icon
  under `~/.local/share`. Notes go to `~/Documents/Saber (personalized)` (dart-define
  `LOCAL_DIRECTORY_NAME`), settings to `~/.local/share/<id>`; the Flathub Saber keeps
  `~/Documents/Saber`. Both sync to the same Nextcloud `Saber` folder if you log in to both.
  Update check is off. `LINUX_INSTALL_LABEL` in `dev.local.env` renames all of it.
- **Android builds on the laptop** (set up 2026-10-19, no Android Studio): Google's command-line
  tools in `~/Android/Sdk/cmdline-tools/latest`, NDK via `sdkmanager "ndk;28.2.13676358"`,
  licenses via `flutter doctor --android-licenses`, and `JAVA_HOME=/usr/lib/jvm/java-21-openjdk`
  in `scripts/dev.local.env` (fine: that `bin` has no `rustc`). If cargo reports `can't find
  crate for core`, Gradle got `/usr/bin` first on PATH: check `JAVA_HOME` reaches Flutter, then
  `cd android && ./gradlew --stop` so the daemon restarts with the right PATH.
- The release app on the tablet isn't debuggable, so `run-as` (note decoding below) needs a
  `--debug` build.

## New machine setup

> [!WARNING]
> Installing a differently-signed build (e.g. over the Play Store Saber) makes Flutter
> **uninstall the old app and wipe its notes**. Use `scripts/dev.sh` (`adb install -r`), which
> refuses instead. Sync to Nextcloud first anyway.

**Install:**
- **Flutter 3.47.7** (stable, includes Dart 3.13.5). `pubspec.yaml` needs ≥ 3.47.0.
- **Android SDK:** compileSdk 37, NDK `28.2.13676358`, platform-tools (`adb`). Android Studio
  installs these. Studio needs the **Flutter** plugin and the Flutter SDK path set.
- **JDK 21, not one under `/usr`.** Gradle downloads one to `~/.gradle/jdks/`.
  `scripts/dev.sh` picks it automatically. With the system JDK, Flutter puts `/usr/bin` first and
  a distro `rustc` breaks the build (`can't find crate for core`).
- **rustup** (not the distro's `rust`/`cargo` packages, or keep them but use the JDK above).
  Toolchain `1.97.1` with Android targets, needed by `irondash_engine_context`. It installs itself
  on the first build, or ahead of time:

  ```sh
  rustup toolchain install 1.97.1
  rustup target add --toolchain 1.97.1 aarch64-linux-android armv7-linux-androideabi x86_64-linux-android i686-linux-android
  ```

- **Linux desktop build** (Fedora names; Debian/Ubuntu equivalents in `.github/shared_workflows/install_apt_dependencies`):

  ```sh
  sudo dnf install clang cmake ninja-build pkgconf-pkg-config gtk3-devel \
    webkit2gtk4.1-devel libsoup3-devel libsecret-devel jsoncpp-devel libunwind-devel
  ```

- **`gh`** (GitHub CLI), logged in: `gh auth login`.

**Get the code:**

```sh
gh repo clone Delici0u-s/saber && cd saber
git remote add upstream https://github.com/saber-notes/saber.git
printf 'FLUTTER_ROOT=%s\n' "/path/to/flutter" > scripts/dev.local.env   # only if flutter isn't on PATH
flutter pub get
cd .. && gh repo clone Delici0u-s/perfect-freehand-dart   # only needed to work on the library
```

## Everyday commands

| What | Command |
|---|---|
| Build + install + launch on tablet (release, keeps data) | `scripts/dev.sh android` |
| Only build / only install | `scripts/dev.sh android build` / `install` |
| Debug build (slow; for logs) | `scripts/dev.sh android --debug` |
| Linux desktop (dev build from `build/`) | `scripts/dev.sh linux` |
| Install / update "Saber (personalized)" for daily use (next to the Flathub Saber) | `scripts/dev.sh linux install` (`uninstall` removes it, keeps notes) |
| Tests | `flutter test` (20 golden tests also fail on unmodified `main` outside Docker, as of 2026-10-19; `./test.sh` runs them in Docker) |
| Analyzer | `flutter analyze` (16 info-level lints are expected) |
| After editing `lib/i18n/en.i18n.yaml` | `dart run slang` |
| Library tests | `flutter test`, and `dart fix --compare-to-golden` inside `test_fixes/` (that's what CI runs) |
| App logs from the tablet | `adb logcat \| grep flutter` |

Notes:
- **Saber upstream doesn't accept AI-generated code** (`.github/CONTRIBUTING.md`), so fork work
  stays personal. `perfect-freehand-dart` has no written rule; PR #27 discloses the AI help.
- Release builds take 3–4 minutes (most of it Gradle). Iterate with tests, install at the end.
- Tablet: Lenovo Tab M11 (TB330FU), Android 15, adb id `HVA6JH1W`.

## Decode a note's strokes (`.sbn2`)

```sh
adb exec-out run-as com.adilhanney.saber cat "app_flutter/Saber/<note>.sbn2" > note.sbn2
python3 -I dump_sbn2.py note.sbn2   # prints each stroke's points as (x, y, pressure)
```

<details><summary><code>dump_sbn2.py</code></summary>

```python
"""Minimal BSON reader: lists strokes in a Saber .sbn2 file."""
import struct
import sys


def read_cstring(b, i):
    end = b.index(b"\x00", i)
    return b[i:end].decode(), end + 1


def read_doc(b, i):
    size = struct.unpack_from("<i", b, i)[0]
    end = i + size - 1
    i += 4
    out = {}
    while i < end:
        t = b[i]
        i += 1
        key, i = read_cstring(b, i)
        if t == 0x01:
            out[key] = struct.unpack_from("<d", b, i)[0]; i += 8
        elif t == 0x02:
            n = struct.unpack_from("<i", b, i)[0]
            out[key] = b[i + 4:i + 4 + n - 1].decode(); i += 4 + n
        elif t in (0x03, 0x04):
            d, i = read_doc(b, i)
            out[key] = list(d.values()) if t == 0x04 else d
        elif t == 0x05:
            n = struct.unpack_from("<i", b, i)[0]
            out[key] = b[i + 5:i + 5 + n]; i += 5 + n
        elif t == 0x08:
            out[key] = bool(b[i]); i += 1
        elif t == 0x0A:
            out[key] = None
        elif t == 0x10:
            out[key] = struct.unpack_from("<i", b, i)[0]; i += 4
        elif t == 0x12:
            out[key] = struct.unpack_from("<q", b, i)[0]; i += 8
        else:
            raise ValueError(f"unsupported BSON type {t:#x} at key {key}")
    return out, end + 1


doc, _ = read_doc(open(sys.argv[1], "rb").read(), 0)
for pi, page in enumerate(doc.get("z", [])):
    for si, s in enumerate(page.get("s", [])):
        pts = [struct.unpack("<" + "f" * (len(p) // 4), p) for p in s["p"]]
        print(f"page {pi} stroke {si} ({s.get('ty')}): {len(pts)} pts")
        for p in pts:
            print("   ", tuple(round(v, 3) for v in p))
```

</details>
