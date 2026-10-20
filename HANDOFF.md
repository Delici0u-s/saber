# Handoff (2026-10-20, paused here; continue in a new chat)

Where things stand, what's left, and how to set up a new machine. The feature plans (with every
decision you made) are in `FEATURE_PLANS.md`; read it together with this.

## State

All work is committed: the features in `8a432da`, the README, this handoff and
`FEATURE_PLANS.md` in the `personal:` commit after it. You tested everything on the PC and the
tablet ("all things work nicely").

- `main` of `Delici0u-s/saber` is the only branch. Saber gets `perfect_freehand` from the fork's
  `personal` branch via `dependency_overrides` in `pubspec.yaml`; `pubspec.lock` pins the commit.
- Untracked and not for committing: `test/failures/` (output of failing goldens),
  `INVESTIGATION_NOTES.md` (your notes).
- Checks at the end of the session: the full suite fails only the 20 golden tests that also fail
  on unmodified `main` outside Docker (see *Gotchas*), `flutter analyze` shows the usual 16 infos,
  `dart format` is clean.

## How we work (your preferences)

- **Plan features before building** (`FEATURE_PLANS.md`): how other apps do it, the design, options
  and questions; build only after your OK. Bug fixes and requested tweaks go straight to code.
- **Look before reporting:** UI changes were checked in test renders (see *Gotchas*), on phone and
  desktop sizes, and with tests through the real editor.
- Your global rules (`~/.claude/CLAUDE.md`): no hardcoding (sizes from content, one home per value,
  test at extremes), and ask before anything that can lose data (installs over other builds!).

## Built (2026-10-19 evening and 2026-10-20, `8a432da`)

| Feature | What it does | Main code |
|---|---|---|
| Ruler fixes | Corners: strokes go round outer corners, stop at inner ones; labels fit by their box; clipped to the canvas; 1° steps (15° catch within 0.75°); degrees/radians; Geodreieck after the mizi drawing (edge marks along their angle) | `components/canvas/ruler.dart` |
| Sync fix | Downloads wait for the write; a failed reload keeps the open note | `nextcloud/saber_syncer.dart`, `EditorState._reloadInPlace` |
| Search | Search button on *Recent* and *Browse*: notes by name/folder, with thumbnails | `components/home/search_notes_button.dart` |
| Line styles in shapes | Hold to shape keeps dashes/dots; preview in the style | `tools/pen.dart` (`toShape`, `outlineStroke`), `_canvas_painter.dart` |
| Opacity | Slider per pen (fountain, ballpoint, pencil), saved as colour alpha | `toolbar/opacity_picker.dart` |
| Scribble to erase | Setting, off by default; pens and pencil only | `tools/scribble_erase.dart` |
| Lasso actions | Box with corner/side/rotate handles, thickness slider, one undo step each | `editor/selection_transform.dart`, `_SelectionChange` in `editor.dart` |
| Zoom window | Panel mirroring a box on the page; auto-advance; view follows | `components/canvas/zoom_window.dart` |
| Side by side | Second pane: note (writable, lockable, own undo) or PDF | `pages/editor/side_by_side.dart`, `EditorEmbedding` |
| Double-tap to erase | Setting: off / finger or mouse (default) / pen / all; takes back the taps' dots | `tools/double_tap_to_erase.dart`, `_onDoubleTap` |
| Tape | Highlighter-tab mode; tap to reveal/hide; not saved revealed; hold to shape | `tools/tape.dart`, `paintTape` |
| Toolbar | Groups *Insert* (image, text, PDF) and *Tools* (ruler, zoom window, laser): inline when they fit, else a button opening named rows; share in the app bar | `toolbar/toolbar.dart` |
| PDF pages | Choose pages when importing (thumbnails, all/none, ranges) | `pages/editor/pdf_page_chooser.dart` |

Also fixed on the way: selection handles, zoom-box handles and the eraser outline were sized by
zoom only (2.5× too small on phones); duplicated images weren't offset; the pen tab overflowed on
phones (tool options now scroll); the stroke being drawn, selections, the shape preview and
Ctrl+Z are tied to their own editor (needed for side by side).

## What's next

1. **Customise toolbar** (FEATURE_PLANS.md section 10a): you were asked whether to plan it now or
   when more tools exist; no answer yet.
2. **Research more tools** (section 11), by category: filling and colour, measuring and
   constructing, shapes and objects, editing ink. The bucket was one example, not the plan.
3. **Shapes** (not started): placing shapes, more shapes, editable/dynamic shapes, reshaping by
   anchor points. Investigate and plan first.

Known limitations, accepted for now:
- The zoom window doesn't show typed text (each page's text editor can only be shown once), and the
  ruler doesn't act on strokes written in it.
- The phone toolbar needs two rows (12 always-visible buttons don't fit one).
- Labels under the ruler's ring or across the protractor's marks are left out.

### Housekeeping

- Saber has only `main` now (the README says the fork is personal and unmaintained).

### Gotchas

- **The 20 golden tests that always fail outside Docker:** glassy container, home themes for iOS
  and macOS, the login pages, `v9_low_point_count.sbn` and 7 of the screenshot goldens. To tell new
  failures from these, run the same tests on `HEAD` in a worktree (`git worktree add <dir> HEAD`)
  and compare. Home-theme goldens compare with a tolerance, so small changes (an icon) may only
  fail the dark ones.
- **Looking at UI in tests:** a scratch test under `test/_scratch_render/` (delete it afterwards)
  that pumps the editor in `ScreenshotApp`, calls `tester.loadAssets()`, and writes
  `matchesGoldenFile('<absolute path>.png')` with `--update-goldens`; for widgets outside the editor,
  load the font with `FontLoader('AtkinsonHyperlegibleNext')` (and the icon fonts by family name).
- **Editor tests:** use `testGoldens` with `ScreenshotApp` (the device frame scales the editor, so
  map page points with `page.renderBox!.localToGlobal`), `pumpAndSettle()` once before drawing
  (the new note loads first), and draw with small moves and a pump between them. Double-tap tests
  need explicit pointer time stamps (`gesture.down(…, timeStamp:)`).
- After editing `lib/i18n/en.i18n.yaml`: `dart run slang`. New imports out of order:
  `dart fix --apply --code=directives_ordering <file>`.

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
