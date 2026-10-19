> [!IMPORTANT]
> **Personal fork:** not the official Saber. For the real app, see
> [saber-notes/saber](https://github.com/saber-notes/saber). I just applied some pull requests/features/https://github.com/steveruizok/perfect-freehand-dart/pull/27.
>
> This is a local optimisation for my own use. It **won't be maintained**: no updates from upstream,
> no support, no releases. Everything is on `main`.
>
> Commit links point to where each change was made.
>
> **Fixes**
> - **Invisible dots:** pen taps on Android stylus devices now draw a dot. Fixed in
>   [`perfect_freehand`](https://github.com/Delici0u-s/perfect-freehand-dart/tree/fix/stationary-dots)
>   (upstream PR [#27](https://github.com/steveruizok/perfect-freehand-dart/pull/27)), which
>   `pubspec.yaml` overrides as a git dependency. Remove the override once a release includes it. ([`79a500a`](https://github.com/Delici0u-s/perfect-freehand-dart/commit/79a500a), [`640c910`](https://github.com/Delici0u-s/perfect-freehand-dart/commit/640c910); here [`8304217`](https://github.com/Delici0u-s/saber/commit/8304217b), [`83378a2`](https://github.com/Delici0u-s/saber/commit/83378a22))
> - **Sync:** a save made while that note was uploading is now uploaded too (it used to be dropped). ([`09d1033`](https://github.com/Delici0u-s/saber/commit/09d1033c))
> - **Pencil dots:** taps with the pencil now draw a dot (its taper used to shrink dots to nothing). ([`0ddece1`](https://github.com/Delici0u-s/saber/commit/0ddece13))
> - **Fullscreen:** no more empty bar above the toolbar on Android. ([`3ec0923`](https://github.com/Delici0u-s/saber/commit/3ec09237))
> - **Area eraser:** cuts strokes exactly at its edge; it used to remove whole stretches between a
>   stroke's points, e.g. most of a straight line. ([`6005f64`](https://github.com/Delici0u-s/saber/commit/6005f64a))
> - **Sync flicker:** an open note no longer flickers when changes from another device arrive (also
>   while watching the server): pages, images and unchanged PDFs stay on screen. ([`6d6d1e7`](https://github.com/Delici0u-s/saber/commit/6d6d1e71))
> - **Smooth strokes zoomed out:** strokes keep their full detail down to 0.5x zoom (upstream drops to
>   every 4th point below 0.9x, so handwriting showed corners at around 0.7x). ([`3e39cc4`](https://github.com/Delici0u-s/saber/commit/3e39cc4d))
>
> **Features**
> - **Pressure-sized dots:** a tap's dot is as big as the hardest pressure applied, and taps are
>   drawn round (also in `perfect_freehand` PR #27). ([`8e380a6`](https://github.com/Delici0u-s/perfect-freehand-dart/commit/8e380a6), [`92c70b3`](https://github.com/Delici0u-s/perfect-freehand-dart/commit/92c70b3); here [`696e65c`](https://github.com/Delici0u-s/saber/commit/696e65cf), [`6df0724`](https://github.com/Delici0u-s/saber/commit/6df0724f), [`b65411f`](https://github.com/Delici0u-s/saber/commit/b65411f2))
> - **Sync while open:** checks Nextcloud for changes every minute (setting *Check for changes*), when the
>   app is resumed and, with *Sync on save*, after each save. The open note reloads when a newer version
>   arrives and it has no unsaved changes. ([`09d1033`](https://github.com/Delici0u-s/saber/commit/09d1033c))
> - **Selection:** one selection button; tap it again to pick lasso or box selection.
>   The selection and eraser buttons show the active mode's icon. ([`59641c0`](https://github.com/Delici0u-s/saber/commit/59641c04))
> - **Eraser outline:** a dashed circle shows the eraser's size while erasing. ([`a671383`](https://github.com/Delici0u-s/saber/commit/a6713837))
> - **Crop images:** *Crop* in an image's long-press menu (pictures only). Crops the pixels, so the result
>   looks the same in other Saber versions; undo restores the original. ([`256e423`](https://github.com/Delici0u-s/saber/commit/256e423e))
> - **Hold to shape:** hold any pen still at the end of a stroke (setting *Hold to shape*, default 1s)
>   to turn it into a line, rectangle, circle, triangle or star. ([`8c142f2`](https://github.com/Delici0u-s/saber/commit/8c142f25))
> - **Line styles:** solid, dashed, dotted or dash-dot strokes, picked in the pen and pencil tabs (each
>   pen remembers its own). Other Saber versions draw these strokes solid. ([`6005f64`](https://github.com/Delici0u-s/saber/commit/6005f64a))
> - **Real size:** a HUD button (top left, next to the zoom lock) zooms so a page shows at its
>   physical size: A4 wide, or the paper picked in the *Real size paper* setting (A5, B5, Letter, A3).
>   Uses the screen density reported by Android or by the monitor on Linux, or the *Screen density*
>   setting. ([`bac4cb5`](https://github.com/Delici0u-s/saber/commit/bac4cb52), [`453e918`](https://github.com/Delici0u-s/saber/commit/453e9182))
> - **Paper spacings:** background line height is shown in mm, with presets (5, 6, 7, 8, 10 mm,
>   e.g. 5 mm squared paper). Spacing is a whole number of page units, so 5 mm is 5.04 mm. ([`9f9ec1b`](https://github.com/Delici0u-s/saber/commit/9f9ec1b9))
> - **Finer settings:** line height and highlighter size step by 1; faster options for auto-save (2s)
>   and shape recognition (0.25s). ([`5462702`](https://github.com/Delici0u-s/saber/commit/54627021), [`55119c5`](https://github.com/Delici0u-s/saber/commit/55119c51))
> - **Build script:** `scripts/dev.sh android|linux [build|install|run] [--debug]`. Machine-specific
>   paths go in `scripts/dev.local.env` (see the script's header). Android installs keep app data and
>   refuse to replace a differently signed (e.g. Play Store) install. `linux install`/`uninstall` add or remove it
>   next to the official Saber (see *Installing this fork* below). ([`83378a2`](https://github.com/Delici0u-s/saber/commit/83378a22), [`d66613d`](https://github.com/Delici0u-s/saber/commit/d66613dc), [`e731873`](https://github.com/Delici0u-s/saber/commit/e7318730), [`5a852a2`](https://github.com/Delici0u-s/saber/commit/5a852a27))
>
> **Merged upstream pull requests**
> - [#1829](https://github.com/saber-notes/saber/pull/1829): move selections between pages ([`ef7b0a5`](https://github.com/Delici0u-s/saber/commit/ef7b0a58))
> - [#1823](https://github.com/saber-notes/saber/pull/1823): prevent adding PDFs as images ([`41e4682`](https://github.com/Delici0u-s/saber/commit/41e46828))
> - [#1718](https://github.com/saber-notes/saber/pull/1718): box selection tool (without the PR's
>   colour bar restyle), adapted to #1829 ([`a6d1984`](https://github.com/Delici0u-s/saber/commit/a6d19845))
> - [#1761](https://github.com/saber-notes/saber/pull/1761): area eraser ([`f393cdd`](https://github.com/Delici0u-s/saber/commit/f393cdde))
>
> **AI assistance:** the investigation, fixes and features in this fork were made with help from
> Claude (Anthropic). Code in this fork is for personal use and isn't submitted to Saber, whose
> contributing guidelines don't accept AI-generated code.
>
> **Installing this fork**
> - **Dependencies:** Flutter and the system packages are the same as upstream's; see
>   [Build Saber](https://github.com/saber-notes/saber/wiki/build) on the original repo's wiki.
>   `pubspec.yaml` names the minimum Flutter version.
> - **Get the code:** `git clone https://github.com/Delici0u-s/saber && cd saber`. If `flutter` isn't on
>   your `PATH`, put `FLUTTER_ROOT=/path/to/flutter` in `scripts/dev.local.env`.
> - **Linux:** `scripts/dev.sh linux install` builds a release and installs *Saber (personalized)* for
>   your user, next to any other Saber: app menu entry, `saber-personalized` command, its own settings
>   and its own notes folder `~/Documents/Saber (personalized)`. Rerun it to update;
>   `scripts/dev.sh linux uninstall` removes the app but keeps the notes and settings.
> - **Android:** `scripts/dev.sh android` builds, installs and launches on the connected device.
>   It replaces the official Saber (same app id) and refuses if that one is signed differently,
>   because replacing it would delete its notes.

# <img src="https://github.com/saber-notes/saber/raw/main/assets/icon/icon.png" width="30" height="30" alt="Logo"> Saber

[<img src='https://github.com/saber-notes/saber/blob/main/assets_raw/badges/google-play-badge.svg'
    alt='Get it on Google Play'
    height=50>][google_play]
&nbsp;
[<img src="https://github.com/saber-notes/saber/blob/main/assets_raw/badges/f-droid-badge.svg"
    alt="Get it on F-Droid"
    height=50>][f-droid]
&nbsp;
[<img src="https://github.com/saber-notes/saber/blob/main/assets_raw/badges/app-store-badge.svg"
    alt="Download on the App Store"
    height=50>][app_store]
&nbsp;
[<img src="https://github.com/saber-notes/saber/blob/main/assets_raw/badges/windows-badge.png"
    alt="Download for Windows"
    height=50>][download_windows]
&nbsp;
[<img src="https://github.com/saber-notes/saber/blob/main/assets_raw/badges/flathub-badge.svg"
    alt="Download on Flathub"
    height=50>][flathub]
&nbsp;
[<img src="https://github.com/saber-notes/saber/blob/main/assets_raw/badges/appimage-logo.svg"
    alt="Get it as an AppImage"
    height=50>][download_appimage]

[English](https://github.com/saber-notes/saber/blob/main/README.md) |
[čeština](https://github.com/saber-notes/saber/blob/main/README-cs.md) |
[Deutsch](https://github.com/saber-notes/saber/blob/main/README-de.md) |
[中文 (简体中文, 中国)](https://github.com/saber-notes/saber/blob/main/README-zh-CN.md) |
[中文 (繁體, 台灣)](https://github.com/saber-notes/saber/blob/main/README-zh-TW.md) |
[العربية](https://github.com/saber-notes/saber/blob/main/README-ar.md) |
[Tiếng Việt](https://github.com/saber-notes/saber/blob/main/README-vi.md) |
[Bahasa Indonesia](https://github.com/saber-notes/saber/blob/main/README-id.md)

Saber is the notes app built for handwriting.

It's designed to be as simple and intuitive as possible, while still delivering unique features that you'll actually use. Additionally, Saber is available across all your devices, large and small, and syncs between them seamlessly.

Notably, it can invert your notes when you're in dark mode. This allows you to write with white ink on a black background, which is much easier on the eyes in low-light environments like when the teacher turns off the lights in class.
Images and PDFs are also inverted, so you can still use a digital printout or a textbook without the fuss.

Saber uses a dual-password system to protect your notes from anyone but you, even if they have complete control over the server. You can safely store your notes on the official Saber server, another server, or even host your own!

The app is completely open-source so that anyone can view the source code and see exactly what it's doing and how it handles your data. Many other note-taking apps are closed-source and proprietary, meaning that their inner workings are a mystery to the public.

As someone who studies maths, highlighting multi-line equations was always a hassle with other apps, where the highlighter would change color when it overlapped with itself. Another problem I had was that in some apps, the highlighter would render on top of the text, fading it out and making it hard to read.
Saber's highlighter has no such issues. It utilizes canvas compositing to render the highlighter in a way that is consistent with/better than traditional paper, where it handles overlaps and maintains color consistency.

Saber has everything you need to keep your notes organized. Create folders inside folders inside folders to your heart's content with no limit on the number of nested folders. And even though a note may be buried deep within a nested folder, you can still access it easily with your most recent notes always available on the home screen.

Discover a whole new way to capture and organize your thoughts with Saber. Whether you're a student, professional, or creative mind, Saber is your trusted companion for digital handwriting. Download now and let your ideas flow freely!

[![Latest release](https://img.shields.io/github/v/release/saber-notes/saber)](https://github.com/saber-notes/saber/releases/latest)
[![Flathub](https://img.shields.io/flathub/v/com.adilhanney.saber)](https://flathub.org/apps/details/com.adilhanney.saber)
[![F-Droid](https://img.shields.io/f-droid/v/com.adilhanney.saber)](https://f-droid.org/en/packages/com.adilhanney.saber/)
[![GitHub downloads](https://img.shields.io/github/downloads/saber-notes/saber/total?label=GitHub%20downloads)](https://github.com/saber-notes/saber/releases)
[![Flathub downloads](https://img.shields.io/flathub/downloads/com.adilhanney.saber?label=Flathub%20downloads)](https://flathub.org/apps/details/com.adilhanney.saber)
[![GitHub Sponsors](https://img.shields.io/github/sponsors/adil192)](https://github.com/sponsors/adil192)
[![License](https://img.shields.io/github/license/saber-notes/saber)](https://github.com/saber-notes/saber/blob/main/LICENSE.md)
[![Translation status](https://hosted.weblate.org/widget/saber-notes/saber/svg-badge.svg)](https://hosted.weblate.org/engage/saber-notes/)
[![Codecov](https://codecov.io/gh/saber-notes/saber/branch/main/graph/badge.svg?token=EGQSN0THW2)](https://codecov.io/gh/saber-notes/saber)

<details open>
<summary>Tap to show/hide screenshots</summary>

<div>
<img src="https://github.com/saber-notes/saber/raw/main/metadata/en-US/images/phoneScreenshots/1_home.png" width="180">
<img src="https://github.com/saber-notes/saber/raw/main/metadata/en-US/images/phoneScreenshots/2_editor.png" width="180">
<img src="https://github.com/saber-notes/saber/raw/main/metadata/en-US/images/phoneScreenshots/3_login.png" width="180">
<img src="https://github.com/saber-notes/saber/raw/main/metadata/en-US/images/phoneScreenshots/4_settings.png" width="180">
</div>
</details>

## Features

Please see [#1 Saber progress][progress].

## Install

Please see
[Install Saber](https://github.com/saber-notes/saber/wiki/install)
on the wiki.

## Build from source

Please see
[Build Saber](https://github.com/saber-notes/saber/wiki/build)
on the wiki.

## Links

- [Nextcloud server][nextcloud]
- [Privacy policy][privacy]
- [License][license]
- [Releases][releases]

## Translating

All translations are thanks to our community of contributors.

If you'd like to help out translating Saber, head to [Weblate](https://hosted.weblate.org/engage/saber-notes/)!

[![Translation status](https://hosted.weblate.org/widget/saber-notes/multi-auto.svg)](https://hosted.weblate.org/engage/saber-notes/)

Note: To avoid falling back to English, any gaps in the translations are filled
in by machine translation until a human can contribute.

## Supporting Saber

If you like Saber, please consider supporting it by:
- Spreading the word!
- Starring the project on GitHub
- Sponsoring me on [GitHub Sponsors](https://github.com/sponsors/adil192)
- Donating via [PayPal](https://paypal.me/adilhanney)
- Buying more storage on the Nextcloud server: see [Pricing](pricing.md)

## Development notes

Please see
[Maintainer notes](https://github.com/saber-notes/saber/wiki/Maintainer-notes)
on the wiki.


[f-droid]: https://f-droid.org/packages/com.adilhanney.saber/
[flathub]: https://flathub.org/apps/details/com.adilhanney.saber
[google_play]: https://play.google.com/store/apps/details?id=com.adilhanney.saber
[snap]: https://snapcraft.io/saber
[app_store]: https://apps.apple.com/us/app/saber/id1671523739
[download_windows]: https://github.com/saber-notes/saber/releases/download/v1.36.2/SaberInstaller_v1.36.2.exe
[download_appimage]: https://github.com/saber-notes/saber/releases/download/v1.36.2/Saber-1.36.2-x86_64.AppImage

[nextcloud]: https://nc.saber.adil.hanney.org/

[privacy]: https://github.com/saber-notes/saber/blob/main/privacy_policy.md
[license]: https://github.com/saber-notes/saber/blob/main/LICENSE.md

[releases]: https://github.com/saber-notes/saber/releases
[issues]: https://github.com/saber-notes/saber/issues
[progress]: https://github.com/saber-notes/saber/discussions/1

[f-droid-manifest]: https://gitlab.com/fdroid/fdroiddata/-/blob/master/metadata/com.adilhanney.saber.yml
