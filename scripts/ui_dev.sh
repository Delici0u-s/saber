#!/usr/bin/env bash
# Open the dev window: runs 'dev.sh android' and/or 'dev.sh linux install' on a button press and
# shows their progress. Detached (nohup), so the terminal can be closed or reused right away.
#
#   scripts/ui_dev.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/saber-ui-dev"
mkdir -p "$STATE_DIR"

command -v python3 >/dev/null || { echo "error: python3 not found" >&2; exit 1; }
python3 -c 'import tkinter' 2>/dev/null \
  || { echo "error: python3 has no tkinter (Fedora: sudo dnf install python3-tkinter)" >&2; exit 1; }

nohup python3 "$ROOT/scripts/src/ui_dev.py" >"$STATE_DIR/window.log" 2>&1 &
disown
echo "Opened the Saber dev window (its own errors go to $STATE_DIR/window.log)"
