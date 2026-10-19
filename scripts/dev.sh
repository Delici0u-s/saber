#!/usr/bin/env bash
# Build, install and run Saber locally for Android or Linux.
#
#   scripts/dev.sh android [build|install|run] [--debug]   (default: run)
#   scripts/dev.sh linux   [build|install|uninstall|run] [--debug]   (default: run)
#
# Release builds by default (debug builds are much slower on device).
# 'linux install' installs a "Saber (personalized)" for the current user, alongside any other
# Saber: own app id, settings and notes folder (~/Documents/Saber (personalized)), no update
# check. 'linux uninstall' removes it again but keeps its notes and settings.
# Machine-specific settings go in scripts/dev.local.env (gitignored), e.g.:
#   FLUTTER_ROOT=$HOME/Documents/Sources/flutter
#   JAVA_HOME=$HOME/.gradle/jdks/<some-jdk>
#   ANDROID_SERIAL=<adb device id>   # only needed with several devices
#   LINUX_INSTALL_LABEL=personalized # names the linux install (app id, menu entry, notes folder)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_ENV="$ROOT/scripts/dev.local.env"
# shellcheck disable=SC1090
[[ -f "$LOCAL_ENV" ]] && source "$LOCAL_ENV"

die() { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

usage() {
  sed -n '2,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

# --- arguments ---------------------------------------------------------------
TARGET="${1:-}"; [[ -n "$TARGET" ]] || usage 1
shift
ACTION="run"
MODE="release"
for arg in "$@"; do
  case "$arg" in
    --debug) MODE="debug" ;;
    -h|--help) usage ;;
    build|install|uninstall|run) ACTION="$arg" ;;
    *) die "unknown argument: $arg" ;;
  esac
done

# --- tools ---------------------------------------------------------------------
if [[ -n "${FLUTTER_ROOT:-}" ]]; then
  export PATH="$FLUTTER_ROOT/bin:$PATH"
fi
command -v flutter >/dev/null || die "flutter not found: add it to PATH or set FLUTTER_ROOT in $LOCAL_ENV"

# A path dependency (e.g. a locally patched package) must exist before building.
check_path_dependencies() {
  local dep
  while read -r dep; do
    [[ -d "$ROOT/$dep" ]] || die "path dependency '$dep' (from pubspec.yaml) is missing; clone it there first"
  done < <(grep -E '^\s+path:\s*["'\'']?[./]' "$ROOT/pubspec.yaml" | sed -E 's/^\s+path:\s*//; s/["'\'']//g')
}

# Read a value from a project file instead of repeating it here.
project_value() { # <file> <regex with one capture group>
  sed -nE "s/$2/\1/p" "$ROOT/$1" | head -n1
}

# --- android ---------------------------------------------------------------------
# Flutter puts $JAVA_HOME/bin first on the build's PATH. With the system JDK (in /usr),
# that means /usr/bin comes first and a distro rustc shadows rustup's, which breaks the
# Rust-based native assets. So prefer a JDK that isn't under /usr.
pick_java_home() {
  if [[ -n "${JAVA_HOME:-}" && "$JAVA_HOME" != /usr* ]]; then return; fi
  local jdk
  jdk="$(find "$HOME/.gradle/jdks" -mindepth 3 -maxdepth 3 -path '*/bin/java' -printf '%h\n' 2>/dev/null \
    | xargs -r -n1 dirname | sort -V | tail -n1)"
  [[ -n "$jdk" ]] || die "no JDK outside /usr found; set JAVA_HOME in $LOCAL_ENV"
  export JAVA_HOME="$jdk"
}

adb_device() {
  if [[ -n "${ANDROID_SERIAL:-}" ]]; then echo "$ANDROID_SERIAL"; return; fi
  local devices
  mapfile -t devices < <(adb devices | awk 'NR > 1 && $2 == "device" { print $1 }')
  case "${#devices[@]}" in
    0) die "no Android device connected (check the cable and allow USB debugging)" ;;
    1) echo "${devices[0]}" ;;
    *) die "several devices connected (${devices[*]}); set ANDROID_SERIAL" ;;
  esac
}

android_target_platform() { # <adb serial>
  local abi
  abi="$(adb -s "$1" shell getprop ro.product.cpu.abi | tr -d '\r')"
  case "$abi" in
    arm64-v8a) echo android-arm64 ;;
    armeabi-v7a) echo android-arm ;;
    x86_64) echo android-x64 ;;
    *) die "unsupported device ABI: $abi" ;;
  esac
}

android() {
  [[ "$ACTION" != "uninstall" ]] || die "'uninstall' isn't supported for android"
  pick_java_home
  check_path_dependencies
  local serial platform package apk
  package="$(project_value android/app/build.gradle.kts '^\s*applicationId\s*=\s*"([^"]+)".*')"
  [[ -n "$package" ]] || die "couldn't read applicationId from android/app/build.gradle.kts"
  apk="$ROOT/build/app/outputs/flutter-apk/app-$MODE.apk"

  if [[ "$ACTION" == "build" ]]; then
    platform="${ANDROID_TARGET_PLATFORM:-android-arm64}"
  else
    serial="$(adb_device)"
    platform="$(android_target_platform "$serial")"
  fi

  info "Building $MODE APK for $platform (JAVA_HOME=$JAVA_HOME)"
  (cd "$ROOT" && flutter build apk "--$MODE" --target-platform "$platform")
  [[ "$ACTION" == "build" ]] && { info "Built $apk"; return; }

  info "Installing on $serial (keeps app data)"
  local output
  if ! output="$(adb -s "$serial" install -r "$apk" 2>&1)"; then
    echo "$output" >&2
    if grep -q 'INSTALL_FAILED_UPDATE_INCOMPATIBLE' <<<"$output"; then
      die "the installed $package is signed with a different key (e.g. a store version).
       Replacing it requires uninstalling it, which DELETES its local data.
       Sync or back up your notes first, then uninstall it yourself and rerun."
    fi
    die "install failed"
  fi

  if [[ "$ACTION" == "run" ]]; then
    info "Launching $package"
    adb -s "$serial" shell monkey -p "$package" -c android.intent.category.LAUNCHER 1 >/dev/null
  fi
}

# --- linux -----------------------------------------------------------------------
linux_bundle() { # prints the bundle dir that `flutter build linux` fills
  local arch
  case "$(uname -m)" in
    x86_64) arch=x64 ;;
    aarch64) arch=arm64 ;;
    *) die "unsupported architecture: $(uname -m)" ;;
  esac
  echo "$ROOT/build/linux/$arch/$MODE/bundle"
}

linux_build() { # [extra flutter args...]
  info "Building $MODE Linux app"
  local log
  log="$(mktemp)"
  if ! (cd "$ROOT" && flutter build linux "--$MODE" "$@") 2>&1 | tee "$log"; then
    if grep -q 'required packages were not found' "$log"; then
      echo >&2
      echo "Missing system libraries (pkg-config names):" >&2
      grep -E '^\s+- ' "$log" | sort -u >&2
      echo "Install their -devel packages (Fedora: 'dnf provides \"pkgconfig(<name>)\"' finds them)." >&2
      echo "CMake names the last version it tried; check the plugin's CMakeLists.txt for newer ones it accepts." >&2
    fi
    rm -f "$log"
    die "linux build failed"
  fi
  rm -f "$log"
}

# The separately installed app: everything is derived from the project and LINUX_INSTALL_LABEL.
linux_install_paths() {
  local label="${LINUX_INSTALL_LABEL:-personalized}"
  [[ "$label" =~ ^[A-Za-z0-9_]+$ ]] || die "LINUX_INSTALL_LABEL may only use letters, digits and _ (it's part of the app id)"
  local base_id data_home
  base_id="$(project_value linux/CMakeLists.txt '^set\(APPLICATION_ID "([^"]+)"\).*')"
  [[ -n "$base_id" ]] || die "couldn't read APPLICATION_ID from linux/CMakeLists.txt"
  data_home="${XDG_DATA_HOME:-$HOME/.local/share}"

  INSTALL_LABEL="$label"
  INSTALL_ID="$base_id.$label"
  DESKTOP_TEMPLATE="$ROOT/flatpak/$base_id.desktop"
  INSTALL_DIR="$HOME/.local/lib/$INSTALL_ID"
  INSTALL_MARKER="$INSTALL_DIR/.installed-by-dev.sh"
  INSTALL_LAUNCHER="$HOME/.local/bin/$BINARY-$label"
  INSTALL_DESKTOP="$data_home/applications/$INSTALL_ID.desktop"
  INSTALL_ICON_SOURCE="$ROOT/$(project_value snap/snapcraft.yaml '^icon:\s*(\S+).*')"
  INSTALL_ICON="$data_home/icons/hicolor/scalable/apps/$INSTALL_ID.${INSTALL_ICON_SOURCE##*.}"
  INSTALL_SETTINGS_DIR="$data_home/$INSTALL_ID"
  local folder
  folder="$(project_value lib/data/file_manager/file_manager.dart "^\s*static const appRootDirectoryPrefix = '([^']+)'.*")"
  [[ -n "$folder" ]] || die "couldn't read appRootDirectoryPrefix from lib/data/file_manager/file_manager.dart"
  INSTALL_NOTES_FOLDER="$folder ($label)"
}

# Refuse to touch an install dir or launcher this script didn't create.
check_owned_install() {
  if [[ -e "$INSTALL_DIR" && ! -f "$INSTALL_MARKER" ]]; then
    die "$INSTALL_DIR exists but wasn't installed by this script; move it away first"
  fi
  if [[ -e "$INSTALL_LAUNCHER" || -L "$INSTALL_LAUNCHER" ]] \
    && [[ "$(readlink "$INSTALL_LAUNCHER")" != "$INSTALL_DIR/$BINARY" ]]; then
    die "$INSTALL_LAUNCHER exists and isn't this script's launcher; move it away first"
  fi
}

refresh_desktop_caches() {
  command -v update-desktop-database >/dev/null && update-desktop-database -q "$(dirname "$INSTALL_DESKTOP")" || true
  command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -t "${INSTALL_ICON%/scalable/*}" || true
}

linux_install() {
  linux_install_paths
  [[ -f "$DESKTOP_TEMPLATE" ]] || die "desktop file template $DESKTOP_TEMPLATE is missing"
  [[ -f "$INSTALL_ICON_SOURCE" ]] || die "icon $INSTALL_ICON_SOURCE (from snap/snapcraft.yaml) is missing"
  check_owned_install

  SABER_APPLICATION_ID="$INSTALL_ID" linux_build \
    --dart-define=LOCAL_DIRECTORY_NAME="$INSTALL_NOTES_FOLDER" \
    --dart-define=UPDATE_CHECK=false

  info "Installing to $INSTALL_DIR (notes and settings live elsewhere and are kept)"
  local staging="$INSTALL_DIR.new"
  rm -rf "$staging"
  mkdir -p "$(dirname "$INSTALL_DIR")"
  cp -a "$(linux_bundle)" "$staging"
  touch "$staging/.installed-by-dev.sh"
  rm -rf "$INSTALL_DIR"
  mv "$staging" "$INSTALL_DIR"

  mkdir -p "$(dirname "$INSTALL_LAUNCHER")" "$(dirname "$INSTALL_DESKTOP")" "$(dirname "$INSTALL_ICON")"
  ln -sfn "$INSTALL_DIR/$BINARY" "$INSTALL_LAUNCHER"
  cp "$INSTALL_ICON_SOURCE" "$INSTALL_ICON"
  sed -E \
    -e "s/^(Name(\[[^]]*\])?=.*)$/\1 ($INSTALL_LABEL)/" \
    -e "s|^Icon=.*|Icon=$INSTALL_ID|" \
    -e "s|^Exec=[^ ]*|Exec=\"$INSTALL_DIR/$BINARY\"|" \
    -e "s|^StartupWMClass=.*|StartupWMClass=$INSTALL_ID|" \
    "$DESKTOP_TEMPLATE" >"$INSTALL_DESKTOP"
  refresh_desktop_caches

  info "Installed $(sed -nE 's/^Name=//p' "$INSTALL_DESKTOP" | head -n1): app menu, or '$(basename "$INSTALL_LAUNCHER")'"
  info "Notes: Documents/$INSTALL_NOTES_FOLDER, settings: $INSTALL_SETTINGS_DIR"
}

linux_uninstall() {
  linux_install_paths
  check_owned_install
  info "Removing the app (keeps notes in Documents/$INSTALL_NOTES_FOLDER and settings in $INSTALL_SETTINGS_DIR)"
  rm -rf "$INSTALL_DIR"
  rm -f "$INSTALL_LAUNCHER" "$INSTALL_DESKTOP" "$INSTALL_ICON"
  refresh_desktop_caches
}

linux() {
  check_path_dependencies
  BINARY="$(project_value linux/CMakeLists.txt '^set\(BINARY_NAME "([^"]+)"\).*')"
  [[ -n "$BINARY" ]] || die "couldn't read BINARY_NAME from linux/CMakeLists.txt"

  case "$ACTION" in
    install) linux_install; return ;;
    uninstall) linux_uninstall; return ;;
  esac

  linux_build
  local bundle
  bundle="$(linux_bundle)"
  if [[ "$ACTION" == "run" ]]; then
    info "Running $bundle/$BINARY"
    exec "$bundle/$BINARY"
  fi
  info "Built $bundle/$BINARY"
}

case "$TARGET" in
  android) android ;;
  linux) linux ;;
  -h|--help) usage ;;
  *) die "unknown target: $TARGET (use android or linux)" ;;
esac
