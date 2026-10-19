# Handoff (2026-10-19)

Where things stand, what's next, and how to set up a new machine.

## State

| Repo (your forks) | Branch | Commit | What |
|---|---|---|---|
| `Delici0u-s/saber` | `main` = `personal` | `abace742`+ | All fork features (see the README note at the top) |
| `Delici0u-s/perfect-freehand-dart` | `fix/stationary-dots` | `640c910` | Your upstream PR [#27](https://github.com/steveruizok/perfect-freehand-dart/pull/27) |
| same | `personal` | `bf82a2f` | PR + "dot sized by highest pressure" commit |

Saber gets `perfect_freehand` from the fork's **`personal`** branch via `dependency_overrides`
in `pubspec.yaml` (git dependency, fetched by `flutter pub get`).

## Next tasks

### 1. Move the pressure-dot commit into PR #27

```sh
cd perfect-freehand-dart
git switch fix/stationary-dots
git cherry-pick bf82a2f        # "feat: size a tap's dot by the highest pressure applied"
flutter test                   # 62 tests, golden test/example_inputs/stationary_points.png changes with it
git push                       # adds the commit to PR #27
```

Then:
- Mention it in the PR description (a tap's dot now uses the highest pressure; the
  `stationary_points` golden changed).
- Optionally point Saber's override back to `ref: fix/stationary-dots` and drop the fork's
  `personal` branch, since they'd be identical.

### 2. Bug: the dot doesn't always use the highest pressure

The commit only takes the max pressure when **every** point is at **exactly** the same position
(`lib/src/get_stroke_points.dart`, the `pts.every(isAtSamePositionAs)` check). Likely causes:

- **Sub-pixel jitter (most likely):** if the stylus moves even 0.01px during a tap, the check
  fails. The stroke is then drawn as a tiny line, with first-point pressure and smoothing. That
  would explain "only sometimes".
- **Pressure smoothing:** `getStrokeOutlinePoints` starts from an average of the first 10
  pressures (`prevPressure`), and `simulatePressure` changes values too.
- **Saber's side:** `Stroke.optimisePoints` (`lib/components/canvas/_stroke.dart`) drops points
  with null pressure.

Ideas:
- Treat "within a small distance" as stationary instead of exact equality, e.g. within
  `options.size`, like Saber's `Stroke.isDot`.
- Or do the max-pressure step in Saber for `isDot` strokes.

To see real data, pull a note off the tablet (debug builds only, `run-as` needs a debuggable app)
and decode its strokes with the script at the end of this file.

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
| Linux desktop | `scripts/dev.sh linux` |
| Tests | `flutter test` (14 golden tests also fail on unmodified `main` outside Docker; `./test.sh` runs them in Docker) |
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
