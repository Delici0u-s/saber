# Handoff (2026-10-19, updated)

Where things stand, what's next, and how to set up a new machine.

## State

| Repo (your forks) | Branch | Commit | Pushed? | What |
|---|---|---|---|---|
| `Delici0u-s/saber` | `personal` | see `git log` | yes | Fork features + lock on `8808f44` |
| same | `main` | `6d7ce1ba` | yes | **Behind `personal`** (no lock bumps yet) |
| `Delici0u-s/perfect-freehand-dart` | `personal` | `8808f44` | yes | PR + all dot fixes |
| same | `fix/stationary-dots` | `8e380a6` | **no** (local only) | PR [#27](https://github.com/steveruizok/perfect-freehand-dart/pull/27) + 1 squashed pressure commit |

Saber gets `perfect_freehand` from the fork's **`personal`** branch via `dependency_overrides`
in `pubspec.yaml`; `pubspec.lock` pins the commit (`flutter pub upgrade perfect_freehand` bumps it).

### Library commits on `personal` beyond the PR (`640c910`)

| Commit | What | In `fix/stationary-dots`? |
|---|---|---|
| `bf82a2f` | Tap's dot sized by the highest pressure (exact same position only) | yes, squashed into `8e380a6` |
| `492156a` | Same for taps that drift: points within `options.size` of the first count as a tap | yes, squashed |
| `d6ef51f` | Test: 3/4/100 stationary points give the same result as one point | yes, squashed |
| `8808f44` | **Lone point drawn as a round dot** (see below) | **no** |

What each bug was:
- **Pressure** (`492156a`): a real tap drifts by a fraction of a pixel. Then the middle points
  were skipped and the dot used the *last* (lift-off, lightest) point's pressure. Verified on the
  tablet: dots now follow the hardest press.
- **Stretched dots** (`8808f44`, seen on desktop with a thin pen): `getStrokePoints` added a helper
  point 1pt right and down from a lone point (upstream behaviour, also in the JS library), so every
  dot was a tiny diagonal stroke, √2 ≈ 1.4pt longer along ↘ (40% at size 3). Since taps now collapse
  to one point, every tap was affected. Fix: drop the helper point; `getStrokeOutlinePoints`
  already draws a lone point as a round dot. Goldens changed (dots only): `one_point`,
  `two_equal_points`, `stationary_points`, `short_strokes`. New test checks roundness for sizes
  1–100 and 1–100 points.

All checks pass on `personal`: 64 tests, `dart format`, `flutter analyze` (2 known `test_fixes`
infos), `dart fix --compare-to-golden` in `test_fixes/` (2/0).

## Next tasks

### 1. Test the round dots in the app (not done yet)

```sh
scripts/dev.sh linux      # desktop: click, click while nudging, thin + thick pen
scripts/dev.sh android    # tablet: light/hard taps, still the right size and round now
```

### 2. Update PR #27 (you said you'd do the online part yourself)

Decide whether `8808f44` goes into the PR. It changes upstream behaviour for single points
(a reviewer may ask), but without it the PR's taps look stretched. To fold it into the same
single commit on the PR branch:

```sh
cd perfect-freehand-dart
git switch fix/stationary-dots
git reset --soft 640c910                         # undo the local squash commit, keep its changes
git checkout personal -- lib test                # take every file from personal
git diff --cached --stat                         # get_stroke_points.dart, test, 4 goldens
flutter test && git commit                       # one commit, message covering pressure + round dots
git checkout analysis_options.yaml               # flutter test adds a build/** exclude; not ours
git push origin fix/stationary-dots              # updates the PR
```

Or keep `8e380a6` and add `8808f44` as a second commit: `git cherry-pick 8808f44`.

Then add a PR comment (`gh pr comment 27 -R steveruizok/perfect-freehand-dart --body "…"`)
or edit the description (`gh pr view 27 … --json body -q .body > pr.md`, edit,
`gh pr edit 27 … --body-file pr.md`). Mention: taps use the highest pressure, small drift counts
as a tap, lone points are round, and which goldens changed.

### 3. Housekeeping

- Saber `main` is behind `personal` (lock bumps): fast-forward it when happy
  (`git switch main && git merge --ff-only personal && git push`).
- After the PR is updated, Saber's override could point at `ref: fix/stationary-dots` instead of
  `personal`.
- Untracked in Saber, not committed: `INVESTIGATION_NOTES.md` (notes from 2026-10-18),
  `test/failures/` (output of the known failing goldens; deletable).

### Gotchas from this session

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
