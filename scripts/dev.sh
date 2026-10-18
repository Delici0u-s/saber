#!/usr/bin/env bash
# Build, install and run Saber locally for Android or Linux.
#
#   scripts/dev.sh android [build|install|run] [--debug]   (default: run)
#   scripts/dev.sh linux   [build|run]         [--debug]   (default: run)
#
# Release builds by default (debug builds are much slower on device).
# Machine-specific settings go in scripts/dev.local.env (gitignored), e.g.:
#   FLUTTER_ROOT=$HOME/Documents/Sources/flutter
#   JAVA_HOME=$HOME/.gradle/jdks/<some-jdk>
#   ANDROID_SERIAL=<adb device id>   # only needed with several devices
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_ENV="$ROOT/scripts/dev.local.env"
# shellcheck disable=SC1090
[[ -f "$LOCAL_ENV" ]] && source "$LOCAL_ENV"

die() { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

usage() {
  sed -n '2,11p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
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
    build|install|run) ACTION="$arg" ;;
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
linux() {
  [[ "$ACTION" != "install" ]] || die "'install' isn't supported for linux; use build or run"
  check_path_dependencies
  local binary arch bundle
  binary="$(project_value linux/CMakeLists.txt '^set\(BINARY_NAME "([^"]+)"\).*')"
  [[ -n "$binary" ]] || die "couldn't read BINARY_NAME from linux/CMakeLists.txt"
  case "$(uname -m)" in
    x86_64) arch=x64 ;;
    aarch64) arch=arm64 ;;
    *) die "unsupported architecture: $(uname -m)" ;;
  esac
  bundle="$ROOT/build/linux/$arch/$MODE/bundle"

  info "Building $MODE Linux app"
  local log
  log="$(mktemp)"
  if ! (cd "$ROOT" && flutter build linux "--$MODE") 2>&1 | tee "$log"; then
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
  if [[ "$ACTION" == "run" ]]; then
    info "Running $bundle/$binary"
    exec "$bundle/$binary"
  fi
  info "Built $bundle/$binary"
}

case "$TARGET" in
  android) android ;;
  linux) linux ;;
  -h|--help) usage ;;
  *) die "unknown target: $TARGET (use android or linux)" ;;
esac
