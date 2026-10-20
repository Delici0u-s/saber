#!/usr/bin/env python3
"""A small window that runs scripts/dev.sh jobs and shows how far along they are.

Started by scripts/ui_dev.sh. Each job is one dev.sh invocation (see JOBS). Progress is
estimated from the last successful runs of the same job (see Estimator): from the build's own
output when it prints lines that earlier builds printed too, otherwise from how long those
builds took. The first run of a job has nothing to go on and shows a moving bar.
"""

import io
import json
import os
import queue
import re
import signal
import statistics
import subprocess
import sys
import threading
import time
import tkinter as tk
import tkinter.font as tkfont
from dataclasses import dataclass, field
from pathlib import Path
from tkinter import messagebox, ttk
from typing import Any, Callable, cast

ROOT = Path(__file__).resolve().parents[2]
DEV_SH = ROOT / "scripts" / "dev.sh"
STATE_DIR = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local" / "state")) / "saber-ui-dev"
STATE_FILE = STATE_DIR / "state.json"


@dataclass(frozen=True)
class JobSpec:
    name: str
    args: tuple[str, ...]
    description: str


# The jobs the window offers, in display order.
JOBS = (
    JobSpec("Android", ("android",), "Build the APK, install it on the connected device and open it."),
    JobSpec("Linux", ("linux", "install"), "Build and install the separate personal Saber for this user."),
)

STEP_PREFIX = "==> "  # dev.sh's info() prefix
DEBUG_FLAG = "--debug"
HISTORY_RUNS = 3  # successful runs per job the estimate is based on
POLL_MS = 100  # how often the UI drains process output and updates timers
ANIMATION_MS = 30  # frame time of the moving bar while there's no estimate
MAX_LOG_LINES = 5000  # lines kept in an output view; the log file keeps everything
MAX_PROGRESS = 99  # the bar never claims 100% before the job has actually finished
LOG_LINES = 14  # visible output lines when the window opens
SCREEN_FRACTION = 0.8  # the window opens at most this much of the screen
ANSI_ESCAPE = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
NUMBERS = re.compile(r"\d+")  # differ between runs (sizes, versions), so lines match without them
ERROR_LINE = re.compile(r"\berror\b|\bfailed\b|\bfailure\b|exception", re.IGNORECASE)
OK_PREFIX = "✓"  # Flutter's "✓ Built ..." lines

PALETTES = {
    "dark": dict(
        bg="#15171c", surface="#1e2128", raised="#282c35", hover="#323743", border="#2c3039",
        text="#e7e9ee", dim="#8a91a0", faint="#5a606d", accent="#7088ff", accent_hover="#8a9dff",
        on_accent="#0c0f1f", ok="#4cc38a", fail="#f2666b", log_bg="#101216", log_text="#c5cad4",
    ),
    "light": dict(
        bg="#f3f4f7", surface="#ffffff", raised="#eceef3", hover="#e1e4eb", border="#dde1e8",
        text="#1b1e24", dim="#646b78", faint="#a3a9b4", accent="#3d5afe", accent_hover="#5671ff",
        on_accent="#ffffff", ok="#1b9a57", fail="#d63a40", log_bg="#fafbfc", log_text="#2b2f36",
    ),
}

C: dict[str, str] = {}  # the active palette
F: dict[str, tkfont.Font] = {}  # fonts, all derived from the system's default fonts
U = 0  # spacing unit: half a line of body text


# --- persisted state ---------------------------------------------------------------
def load_state() -> dict:
    try:
        return json.loads(STATE_FILE.read_text())
    except (OSError, ValueError):
        return {}


def save_state(state: dict) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    tmp = STATE_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, indent=2))
    tmp.replace(STATE_FILE)


def format_duration(seconds: float) -> str:
    seconds = int(seconds)
    return f"{seconds // 60}:{seconds % 60:02d}"


# --- progress estimate ---------------------------------------------------------------
def milestone_key(line: str) -> str:
    """The part of an output line that's the same in every build."""
    return NUMBERS.sub("#", line).strip()


@dataclass
class Estimate:
    progress: float  # 0..1 of the whole job
    remaining: float  # seconds
    from_output: bool  # placed by a line of the build's output, not only by elapsed time
    overdue: bool  # got as far as the next expected line or the end without reaching it


class Estimator:
    """Estimates a job's progress from its last successful runs.

    Every run records when each distinct output line first appeared ('milestones'). A line
    that all of those runs printed marks a known point of the job: when it appears, the job is
    as far along as it was then in those runs (median share of the run). From that point on, and
    before the first one, time counts against the average duration of those runs. Progress
    stops at the next expected milestone until it appears, and never goes backwards.
    """

    def __init__(self, runs: list[dict]):
        runs = runs[-HISTORY_RUNS:]
        self.duration = statistics.mean(r["duration"] for r in runs) if runs else 0.0
        shared = set.intersection(*(set(r["milestones"]) for r in runs)) if runs else set()
        self.milestones = {
            key: statistics.median(r["milestones"][key] / r["duration"] for r in runs) for key in shared
        }
        self.anchor = (0.0, 0.0)  # (elapsed, progress) at the last milestone reached
        self.from_output = False
        self.best = 0.0

    def on_line(self, line: str, elapsed: float) -> None:
        progress = self.milestones.get(milestone_key(line))
        if progress is not None and progress > self.anchor[1]:
            self.anchor = (elapsed, progress)
            self.from_output = True

    def estimate(self, elapsed: float) -> Estimate | None:
        if not self.duration:
            return None
        at, progress = self.anchor
        upcoming = [p for p in self.milestones.values() if p > progress]
        cap = min(upcoming, default=MAX_PROGRESS / 100)
        progress = progress + (elapsed - at) / self.duration
        self.best = max(self.best, min(progress, cap))
        return Estimate(self.best, (1 - self.best) * self.duration, self.from_output, progress >= cap)


def system_theme() -> str:
    try:
        scheme = subprocess.run(["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"],
                                capture_output=True, text=True, timeout=2).stdout
    except (OSError, subprocess.TimeoutExpired):
        return "light"
    return "dark" if "dark" in scheme else "light"


def git_summary() -> str:
    def git(*args: str) -> str:
        return subprocess.run(["git", "-C", str(ROOT), *args], capture_output=True, text=True,
                              timeout=5).stdout.strip()

    try:
        branch = git("rev-parse", "--abbrev-ref", "HEAD")
        head = git("log", "-1", "--format=%h %s")
        changes = len(git("status", "--porcelain").splitlines())
    except (OSError, subprocess.TimeoutExpired):
        return ""
    parts = [branch, head, f"{changes} uncommitted" if changes else ""]
    return "   ·   ".join(p for p in parts if p)


# --- a running dev.sh process --------------------------------------------------------
@dataclass
class Run:
    args: list[str]
    history_key: str
    log_path: Path
    start: float = field(default_factory=time.monotonic)
    end: float | None = None
    process: subprocess.Popen | None = None
    exit_code: int | None = None
    cancelled: bool = False
    steps: list[tuple[str, float]] = field(default_factory=list)  # (text, seconds from start)
    milestones: dict[str, float] = field(default_factory=dict)  # milestone_key: seconds from start

    def elapsed(self) -> float:
        return (self.end or time.monotonic()) - self.start


def spawn(run: Run, job_index: int, events: queue.Queue) -> None:
    """Starts dev.sh and streams its output lines into `events` from a reader thread."""
    run.process = subprocess.Popen(
        [str(DEV_SH), *run.args],
        cwd=ROOT,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        start_new_session=True,  # own process group, so cancel stops flutter and gradle too
    )

    def read() -> None:
        assert run.process and run.process.stdout
        stdout = cast(io.BufferedReader, run.process.stdout)
        buffer = b""
        while chunk := stdout.read1(65536):
            buffer += chunk
            # Spinners rewrite their line with \r; treat that like a new line.
            *lines, buffer = re.split(rb"\r\n|\r|\n", buffer)
            for line in lines:
                events.put((job_index, "line", line.decode(errors="replace")))
        if buffer:
            events.put((job_index, "line", buffer.decode(errors="replace")))
        events.put((job_index, "exit", run.process.wait()))

    threading.Thread(target=read, daemon=True).start()


# --- widgets ---------------------------------------------------------------------------
def label(master, text="", font="body", fg="text", bg="surface", **kw) -> tk.Label:
    return tk.Label(master, text=text, font=F[font], fg=C[fg], bg=C[bg], bd=0, **kw)


def frame(master, bg="surface", **kw) -> tk.Frame:
    return tk.Frame(master, bg=C[bg], bd=0, **kw)


class ElidedLabel(tk.Label):
    """A one-line label that shortens its text with … to the width it gets, instead of asking
    for more room (which would make the window resize whenever the text changes)."""

    def __init__(self, master, text="", font="body", fg="text", bg="surface"):
        super().__init__(master, width=1, anchor="w", font=F[font], fg=C[fg], bg=C[bg], bd=0)
        self.font = F[font]
        self.full = ""
        self.bind("<Configure>", lambda _: self.refit())
        self.set(text)

    def set(self, text: str) -> None:
        if text != self.full:
            self.full = text
            self.refit()

    def natural_width(self) -> int:
        return self.font.measure(self.full)

    def refit(self) -> None:
        width = self.winfo_width()
        text = self.full
        if width > 1 and self.font.measure(text) > width:
            low, high = 0, len(text)
            while low < high:  # longest prefix that fits together with the ellipsis
                mid = (low + high + 1) // 2
                if self.font.measure(text[:mid] + "…") <= width:
                    low = mid
                else:
                    high = mid - 1
            text = text[:low].rstrip() + "…"
        self.configure(text=text)


class FlatButton(tk.Label):
    KINDS = {  # kind: (background, hovered background, text)
        "primary": ("accent", "accent_hover", "on_accent"),
        "secondary": ("raised", "hover", "text"),
        "danger": ("raised", "hover", "fail"),
        "tab": ("surface", "raised", "dim"),
    }

    def __init__(self, master, text: str, command: Callable[[], None], kind="secondary", font="bold"):
        super().__init__(master, text=text, font=F[font], bd=0, cursor="hand2", padx=2 * U, pady=U)
        self.kind, self.command = kind, command
        self.enabled, self.hovered, self.selected = True, False, False
        self.bind("<Enter>", lambda _: self.set_hover(True))
        self.bind("<Leave>", lambda _: self.set_hover(False))
        self.bind("<ButtonRelease-1>", self.click)
        self.paint()

    def click(self, event) -> None:
        inside = 0 <= event.x < self.winfo_width() and 0 <= event.y < self.winfo_height()
        if self.enabled and inside:
            self.command()

    def set_hover(self, hovered: bool) -> None:
        self.hovered = hovered
        self.paint()

    def set_text(self, text: str) -> None:
        if self.cget("text") != text:
            self.configure(text=text)

    def set_enabled(self, enabled: bool) -> None:
        if enabled != self.enabled:
            self.enabled = enabled
            self.configure(cursor="hand2" if enabled else "")
            self.paint()

    def set_selected(self, selected: bool) -> None:
        self.selected = selected
        self.paint()

    def paint(self) -> None:
        bg, hover_bg, fg = self.KINDS[self.kind]
        if self.kind == "tab" and self.selected:
            bg, hover_bg, fg = "raised", "raised", "text"
        if not self.enabled:
            self.configure(bg=C["raised"], fg=C["faint"])
        else:
            self.configure(bg=C[hover_bg if self.hovered else bg], fg=C[fg])


class CheckBox(tk.Canvas):
    """A clearly visible check box, drawn so it looks the same with any Tk theme."""

    def __init__(self, master, variable: tk.BooleanVar, bg="surface"):
        size = F["body"].metrics("linespace")
        super().__init__(master, width=size, height=size, bg=C[bg], highlightthickness=0, bd=0,
                         cursor="hand2")
        self.variable, self.size = variable, size
        variable.trace_add("write", lambda *_: self.draw())
        self.bind("<Button-1>", lambda _: self.toggle())
        self.draw()

    def toggle(self) -> None:
        self.variable.set(not self.variable.get())

    def draw(self) -> None:
        self.delete("all")
        s, line = self.size, max(2, self.size // 9)
        inset = line
        if self.variable.get():
            rounded_rect(self, inset, inset, s - inset, s - inset, s // 4, fill=C["accent"], outline="")
            self.create_line([s * 0.28, s * 0.52, s * 0.44, s * 0.68, s * 0.73, s * 0.34],
                             fill=C["on_accent"], width=line, capstyle="round", joinstyle="round")
        else:
            rounded_rect(self, inset, inset, s - inset, s - inset, s // 4, fill="",
                         outline=C["faint"], width=line)


def rounded_rect(canvas: tk.Canvas, x0, y0, x1, y1, r, **kw) -> None:
    points = [x0 + r, y0, x1 - r, y0, x1, y0, x1, y0 + r, x1, y1 - r, x1, y1,
              x1 - r, y1, x0 + r, y1, x0, y1, x0, y1 - r, x0, y0 + r, x0, y0]
    canvas.create_polygon(points, smooth=True, **kw)


class ProgressBar(tk.Canvas):
    def __init__(self, master, bg="surface"):
        self.thickness = max(4, F["small"].metrics("linespace") // 3)
        super().__init__(master, height=self.thickness, bg=C[bg], highlightthickness=0, bd=0)
        self.value, self.color, self.moving, self.phase = 0.0, C["accent"], False, 0.0
        self.bind("<Configure>", lambda _: self.draw())

    def set(self, value: float | None = None, color: str | None = None) -> None:
        if value is not None:
            self.value = value
        if color is not None:
            self.color = C[color]
        self.draw()

    def set_moving(self, moving: bool) -> None:
        was_moving, self.moving = self.moving, moving
        if moving and not was_moving:
            self.animate()
        self.draw()

    def animate(self) -> None:
        if self.moving:
            self.phase = (self.phase + 0.015) % 1
            self.draw()
            self.after(ANIMATION_MS, self.animate)

    def draw(self) -> None:
        self.delete("all")
        w, h = self.winfo_width(), self.thickness
        if w <= h:
            return
        half = h / 2
        self.create_line(half, half, w - half, half, width=h, capstyle="round", fill=C["raised"])
        span = w - h
        if self.moving:  # a segment sliding across, as there's no estimate to show
            length = span / 4
            start = self.phase * (span + length) - length
            a, b = max(0, start), min(span, start + length)
            if b > a:
                self.create_line(half + a, half, half + b, half, width=h, capstyle="round", fill=self.color)
        elif self.value > 0:
            self.create_line(half, half, half + span * self.value / 100, half, width=h,
                             capstyle="round", fill=self.color)


# --- one job's card -------------------------------------------------------------------
class JobPanel(tk.Frame):
    def __init__(self, master, app: "App", index: int, spec: JobSpec):
        self.border = max(1, U // 4)
        super().__init__(master, bg=C["surface"], highlightthickness=self.border, bd=0)
        self.app, self.index, self.spec = app, index, spec
        self.run: Run | None = None
        self.estimator = Estimator([])
        self.queued = False
        self.log: tk.Text  # set by App, which owns the output pane

        self.selected = tk.BooleanVar(value=app.state.get("selected", {}).get(spec.name, True))
        self.selected.trace_add("write", lambda *_: self.on_selected())

        inner = frame(self)
        inner.pack(fill="both", expand=True, padx=2 * U, pady=2 * U)

        header = frame(inner)
        header.pack(fill="x")
        CheckBox(header, self.selected).pack(side="left", padx=(0, U))
        name = label(header, spec.name, font="heading", cursor="hand2")
        name.pack(side="left")
        self.status = label(header, "", font="bold")
        self.status.pack(side="right")

        self.description = ElidedLabel(inner, spec.description, fg="dim")
        self.description.pack(fill="x", pady=(U // 2, 0))
        self.command = ElidedLabel(inner, "", font="mono_small", fg="faint")
        self.command.pack(fill="x")
        for widget in (header, name, self.description, self.command):
            widget.bind("<Button-1>", lambda _: self.selected.set(not self.selected.get()))

        self.bar = ProgressBar(inner)
        self.bar.pack(fill="x", pady=(2 * U, U))
        meta = frame(inner)
        meta.pack(fill="x")
        self.timer = label(meta, "", font="small", fg="dim")
        self.timer.pack(side="left")
        self.percent = label(meta, "", font="small", fg="dim")
        self.percent.pack(side="right")

        self.steps_frame = frame(inner)
        self.steps_frame.pack(fill="x", pady=(U, 0))
        self.step_rows: list[tuple[tk.Frame, tk.Label, ElidedLabel]] = []

        self.current = ElidedLabel(inner, "", font="mono_small", fg="dim")
        self.current.pack(fill="x", pady=(U, 0))

        buttons = frame(inner)
        buttons.pack(fill="x", side="bottom", pady=(2 * U, 0))
        self.run_button = FlatButton(buttons, "Run only this", lambda: app.start([self]))
        self.cancel_button = FlatButton(buttons, "Cancel", self.cancel, kind="danger")
        self.output_button = FlatButton(buttons, "Show output", lambda: app.show_log(self), kind="tab",
                                        font="body")
        self.output_button.pack(side="left")

        self.refresh()

    # -- state ------------------------------------------------------------------------
    @property
    def running(self) -> bool:
        return self.run is not None and self.run.exit_code is None

    @property
    def busy(self) -> bool:
        return self.running or self.queued

    def args(self) -> list[str]:
        return [*self.spec.args, *([DEBUG_FLAG] if self.app.debug.get() else [])]

    def history_key(self) -> str:
        return " ".join(self.args())

    def history(self) -> list[dict]:
        """The last successful runs of this job, oldest first."""
        return self.app.state.get("runs", {}).get(self.history_key(), [])

    def history_label(self) -> str:
        count = len(self.history()[-HISTORY_RUNS:])
        return "last build" if count == 1 else f"last {count} builds"

    def usual_duration(self) -> float | None:
        runs = self.history()[-HISTORY_RUNS:]
        return statistics.mean(r["duration"] for r in runs) if runs else None

    def log_path(self) -> Path:
        return STATE_DIR / f"{self.spec.name.lower()}.log"

    def natural_width(self) -> int:
        """Width that shows every text of the card unshortened."""
        texts = [self.description, self.command, self.current] + [text for _, _, text in self.step_rows]
        mark = F["body"].measure("✓") + U
        return max(t.natural_width() for t in texts) + mark + 2 * (2 * U + self.border)

    # -- lifecycle --------------------------------------------------------------------
    def set_queued(self) -> None:
        self.queued = True
        self.run = None
        self.app.clear_log(self)
        self.current.set("")
        self.refresh()

    def start(self) -> None:
        self.queued = False
        STATE_DIR.mkdir(parents=True, exist_ok=True)
        self.run = Run(self.args(), self.history_key(), self.log_path())
        self.estimator = Estimator(self.history())
        self.run.log_path.write_text(f"$ scripts/dev.sh {' '.join(self.run.args)}\n")
        self.app.clear_log(self)
        self.current.set("")
        self.app.job_started(self)
        try:
            spawn(self.run, self.index, self.app.events)
        except OSError as error:
            self.on_line(f"error: couldn't start dev.sh: {error}")
            self.on_exit(-1)
            return
        self.refresh()

    def cancel(self) -> None:
        if self.queued:
            self.queued = False
            self.refresh()
            self.app.job_finished()
            return
        run = self.run
        if run and run.process and run.exit_code is None:
            run.cancelled = True
            try:
                os.killpg(run.process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass

    def on_line(self, raw: str) -> None:
        line = ANSI_ESCAPE.sub("", raw).rstrip()
        if not line or not self.run:
            return
        with self.run.log_path.open("a") as f:
            f.write(line + "\n")
        self.app.append_log(self, line)
        elapsed = self.run.elapsed()
        self.run.milestones.setdefault(milestone_key(line), elapsed)
        self.estimator.on_line(line, elapsed)
        if line.startswith(STEP_PREFIX):
            self.run.steps.append((line[len(STEP_PREFIX):], elapsed))
            self.show_steps()
        self.current.set(line)

    def on_exit(self, code: int) -> None:
        run = self.run
        assert run is not None
        run.exit_code, run.end = code, time.monotonic()
        if code == 0:
            self.app.record_success(run)
        self.refresh()
        self.app.job_finished(self, code, run.cancelled)

    def on_selected(self) -> None:
        self.paint_border()
        self.app.remember()

    # -- view -------------------------------------------------------------------------
    def refresh(self) -> None:
        """Updates everything that depends on the job's state."""
        self.command.set(f"$ scripts/dev.sh {' '.join(self.args())}")
        run = self.run
        if self.queued:
            status, color = "Queued", "dim"
        elif run is None:
            status, color = "Ready", "faint"
        elif run.exit_code is None:
            status, color = "Running", "accent"
        elif run.exit_code == 0:
            status, color = "Done", "ok"
        elif run.cancelled:
            status, color = "Cancelled", "dim"
        else:
            status, color = f"Failed (exit {run.exit_code})", "fail"
        self.status.configure(text=f"●  {status}", fg=C[color])

        self.bar.set_moving(self.running and not self.estimator.duration)
        if run is None:
            self.bar.set(0, "accent")
        elif run.exit_code is not None:
            self.bar.set(100 if run.exit_code == 0 or not run.cancelled else self.bar.value, color)
        else:
            self.bar.set(color="accent")
        if run is not None and run.exit_code is not None:
            self.timer.configure(text=f"took {format_duration(run.elapsed())}")
            self.percent.configure(text="")
        elif run is None:
            usual = self.usual_duration()
            text = f"usually takes {format_duration(usual)} ({self.history_label()})" if usual else ""
            self.timer.configure(text=text)
            self.percent.configure(text="")
        self.tick()

        self.run_button.pack_forget()
        self.cancel_button.pack_forget()
        (self.cancel_button if self.busy else self.run_button).pack(side="right")
        self.paint_border()
        self.show_steps()
        self.app.update_start_button()

    def tick(self) -> None:
        if not self.running:
            return
        assert self.run is not None
        elapsed = self.run.elapsed()
        estimate = self.estimator.estimate(elapsed)
        if estimate:
            self.bar.set(100 * estimate.progress)
            left = f"about {format_duration(estimate.remaining)} left"
            if estimate.overdue:
                left += ", slower than usual"
            source = "from build output" if estimate.from_output else f"from {self.history_label()}"
            self.timer.configure(text=f"{format_duration(elapsed)}   ·   {left}   ·   {source}")
            self.percent.configure(text=f"{100 * estimate.progress:.0f}%", fg=C["text"])
        else:
            self.timer.configure(text=f"{format_duration(elapsed)}   ·   first run, no estimate yet")

    def paint_border(self) -> None:
        color = C["accent"] if self.selected.get() else C["border"]
        self.configure(highlightbackground=color, highlightcolor=color)

    def show_steps(self) -> None:
        """Done and current steps of this run, then the remaining ones from the last run."""
        done = self.run.steps if self.run else []
        history = self.history()
        expected = history[-1]["steps"] if history else []
        finished = self.run is not None and self.run.exit_code is not None
        rows = []
        for i, (text, _) in enumerate(done):
            last = i == len(done) - 1
            if last and not finished:
                rows.append(("▸", text, "accent", "text"))
            elif last and self.run and self.run.exit_code != 0:
                rows.append(("✗", text, "dim" if self.run.cancelled else "fail", "text"))
            else:
                rows.append(("✓", text, "ok", "text"))
        if not finished:
            rows += [("○", text, "faint", "faint") for text, _ in expected[len(done):]]

        while len(self.step_rows) < len(rows):
            row = frame(self.steps_frame)
            mark = label(row, "", font="body", width=2, anchor="w")
            mark.pack(side="left")
            text = ElidedLabel(row, "", font="body")
            text.pack(side="left", fill="x", expand=True)
            self.step_rows.append((row, mark, text))
        for i, (row, mark, text) in enumerate(self.step_rows):
            if i < len(rows):
                symbol, step, mark_color, text_color = rows[i]
                mark.configure(text=symbol, fg=C[mark_color])
                text.configure(fg=C[text_color])
                text.set(step)
                row.pack(fill="x")
            else:
                row.pack_forget()


# --- the window ---------------------------------------------------------------------
class App:
    def __init__(self, root: tk.Tk):
        self.root = root
        self.state = load_state()
        self.events: queue.Queue = queue.Queue()
        self.pending: list[JobPanel] = []  # waiting their turn when not running one at a time
        self.shown_log: JobPanel | None = None

        root.title("Saber dev")
        root.configure(bg=C["bg"])
        self.setup_ttk()
        self.debug = tk.BooleanVar(value=self.state.get("debug", False))
        self.parallel = tk.BooleanVar(value=self.state.get("parallel", True))

        page = frame(root, bg="bg")
        page.pack(fill="both", expand=True, padx=3 * U, pady=3 * U)

        header = frame(page, bg="bg")
        header.pack(fill="x")
        label(header, "Saber dev", font="title", bg="bg").pack(anchor="w")
        self.git = ElidedLabel(header, git_summary(), font="mono_small", fg="dim", bg="bg")
        self.git.pack(fill="x", pady=(U // 2, 0))

        cards = frame(page, bg="bg")
        cards.pack(fill="x", pady=(3 * U, 0))
        self.panels = [JobPanel(cards, self, i, spec) for i, spec in enumerate(JOBS)]
        for column, panel in enumerate(self.panels):
            panel.grid(row=0, column=column, sticky="nsew", padx=(0 if column == 0 else 2 * U, 0))
            cards.columnconfigure(column, weight=1, uniform="jobs")

        controls = frame(page, bg="bg")
        controls.pack(fill="x", pady=(3 * U, 0))
        self.start_button = FlatButton(controls, "", self.start_selected, kind="primary", font="heading")
        self.start_button.pack(side="right")
        self.option(controls, "Debug build", self.debug, self.on_debug_changed)
        self.option(controls, "Run at the same time", self.parallel, self.remember)

        output = frame(page)
        output.pack(fill="both", expand=True, pady=(3 * U, 0))
        tabs = frame(output)
        tabs.pack(fill="x", padx=U, pady=U)
        label(tabs, "Output", font="bold").pack(side="left", padx=(U, 2 * U))
        self.tabs = {}
        for panel in self.panels:
            tab = FlatButton(tabs, panel.spec.name, lambda p=panel: self.show_log(p), kind="tab", font="body")
            tab.pack(side="left")
            self.tabs[panel] = tab
        FlatButton(tabs, "Open log file", self.open_log, kind="tab", font="body").pack(side="right")
        self.logs = frame(output, bg="log_bg")
        self.logs.pack(fill="both", expand=True)
        self.logs.rowconfigure(0, weight=1)
        self.logs.columnconfigure(0, weight=1)
        for panel in self.panels:
            panel.log = self.make_log()

        root.protocol("WM_DELETE_WINDOW", self.on_close)
        self.show_log(self.panels[0])
        self.update_start_button()
        self.fit_window()
        self.poll()

    def setup_ttk(self) -> None:
        style = ttk.Style(self.root)
        if "clam" in style.theme_names():
            style.theme_use("clam")
        style.configure("Log.Vertical.TScrollbar", background=C["raised"], troughcolor=C["log_bg"],
                        bordercolor=C["log_bg"], lightcolor=C["raised"], darkcolor=C["raised"],
                        arrowcolor=C["dim"], gripcount=0)
        style.map("Log.Vertical.TScrollbar", background=[("active", C["hover"])])

    def option(self, master, text: str, variable: tk.BooleanVar, on_change: Callable[[], None]) -> None:
        row = frame(master, bg="bg", cursor="hand2")
        row.pack(side="left", padx=(0, 3 * U))
        CheckBox(row, variable, bg="bg").pack(side="left", padx=(0, U))
        name = label(row, text, bg="bg", cursor="hand2")
        name.pack(side="left")
        for widget in (row, name):
            widget.bind("<Button-1>", lambda _: variable.set(not variable.get()))
        variable.trace_add("write", lambda *_: on_change())

    def make_log(self) -> tk.Text:
        holder = frame(self.logs, bg="log_bg")
        holder.grid(row=0, column=0, sticky="nsew")
        log = tk.Text(holder, wrap="word", state="disabled", font=F["mono_small"], width=1, height=LOG_LINES,
                      bg=C["log_bg"], fg=C["log_text"], bd=0, highlightthickness=0, padx=2 * U, pady=U,
                      selectbackground=C["accent"], selectforeground=C["on_accent"],
                      insertbackground=C["text"])
        scroll = ttk.Scrollbar(holder, orient="vertical", command=log.yview, style="Log.Vertical.TScrollbar")
        log.configure(yscrollcommand=scroll.set)
        log.pack(side="left", fill="both", expand=True)
        scroll.pack(side="right", fill="y")
        log.tag_configure("step", foreground=C["accent"], font=F["mono_small_bold"])
        log.tag_configure("error", foreground=C["fail"])
        log.tag_configure("ok", foreground=C["ok"])
        log.tag_configure("command", foreground=C["dim"])
        return log

    def fit_window(self) -> None:
        """Opens the window as big as its content wants, then leaves the size to the user, so
        text changing while jobs run never resizes (or moves) the window."""
        self.root.update_idletasks()
        cards = sum(p.natural_width() for p in self.panels) + 2 * U * (len(self.panels) - 1) + 6 * U
        width = max(self.root.winfo_reqwidth(), cards)
        height = self.root.winfo_reqheight()
        width = min(width, int(self.root.winfo_screenwidth() * SCREEN_FRACTION))
        height = min(height, int(self.root.winfo_screenheight() * SCREEN_FRACTION))
        self.root.geometry(f"{width}x{height}")
        self.root.minsize(min(width, self.root.winfo_reqwidth()), height - self.logs.winfo_reqheight())

    # -- output pane --------------------------------------------------------------------
    def show_log(self, panel: JobPanel) -> None:
        self.shown_log = panel
        panel.log.master.tkraise()
        for p, tab in self.tabs.items():
            tab.set_selected(p is panel)
        for p in self.panels:
            p.output_button.set_selected(p is panel)

    def clear_log(self, panel: JobPanel) -> None:
        panel.log.configure(state="normal")
        panel.log.delete("1.0", "end")
        panel.log.configure(state="disabled")

    def append_log(self, panel: JobPanel, line: str) -> None:
        log = panel.log
        if line.startswith(STEP_PREFIX):
            tag = "step"
        elif line.startswith("$ "):
            tag = "command"
        elif line.startswith(OK_PREFIX):
            tag = "ok"
        elif ERROR_LINE.search(line):
            tag = "error"
        else:
            tag = ()
        at_bottom = log.yview()[1] >= 1.0
        log.configure(state="normal")
        log.insert("end", line + "\n", tag)
        excess = int(log.index("end-1c").split(".")[0]) - MAX_LOG_LINES
        if excess > 0:
            log.delete("1.0", f"{excess + 1}.0")
        log.configure(state="disabled")
        if at_bottom:
            log.see("end")

    def open_log(self) -> None:
        path = self.shown_log.log_path() if self.shown_log else None
        if path and path.exists():
            subprocess.Popen(["xdg-open", str(path)], start_new_session=True,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    # -- starting jobs ------------------------------------------------------------------
    def start_selected(self) -> None:
        self.start([p for p in self.panels if p.selected.get()])

    def start(self, panels: list[JobPanel]) -> None:
        panels = [p for p in panels if not p.busy]
        if not panels:
            return
        self.git.set(git_summary())
        if self.parallel.get():
            for panel in panels:
                panel.start()
            return
        for panel in panels:
            panel.set_queued()
        self.pending += panels
        self.start_next()

    def start_next(self) -> None:
        if any(p.running for p in self.panels):
            return
        self.pending = [p for p in self.pending if p.queued]
        if self.pending:
            self.pending.pop(0).start()

    def job_started(self, panel: JobPanel) -> None:
        if self.shown_log is None or not self.shown_log.running:
            self.show_log(panel)

    def job_finished(self, panel: JobPanel | None = None, code: int = 0, cancelled: bool = False) -> None:
        if panel is not None and not cancelled:
            self.notify(panel, code)
            if code != 0:
                self.show_log(panel)
        self.start_next()

    def update_start_button(self) -> None:
        if not hasattr(self, "start_button"):
            return  # still building the window
        selected = [p for p in self.panels if p.selected.get()]
        idle = [p for p in selected if not p.busy]
        if not selected:
            text = "Select a job above"
        elif not idle:
            text = "Running…"
        else:
            text = "▶   Run " + " + ".join(p.spec.name for p in idle)
        self.start_button.set_text(text)
        self.start_button.set_enabled(bool(idle))

    # -- events -------------------------------------------------------------------------
    def poll(self) -> None:
        try:
            while True:
                index, kind, data = self.events.get_nowait()
                panel = self.panels[index]
                if kind == "line":
                    panel.on_line(data)
                else:
                    panel.on_exit(data)
        except queue.Empty:
            pass
        for panel in self.panels:
            panel.tick()
        self.root.after(POLL_MS, self.poll)

    def on_debug_changed(self) -> None:
        self.remember()
        for panel in self.panels:
            if not panel.busy:
                panel.refresh()  # command and upcoming steps come from the new mode

    def on_close(self) -> None:
        busy = [p for p in self.panels if p.running]
        if busy:
            names = ", ".join(p.spec.name for p in busy)
            if not messagebox.askyesno("Saber dev", f"Still running: {names}.\nStop it and close?",
                                       parent=self.root):
                return
            for panel in busy:
                panel.cancel()
        self.root.destroy()

    def notify(self, panel: JobPanel, code: int) -> None:
        text = f"{panel.spec.name}: " + ("done" if code == 0 else f"failed (exit {code})")
        try:
            subprocess.Popen(["notify-send", "--app-name=Saber dev", "Saber dev", text],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError:
            pass  # no notify-send; the window still shows the result

    # -- persistence --------------------------------------------------------------------
    def remember(self) -> None:
        if not hasattr(self, "panels"):
            return  # still building the window
        self.state["selected"] = {p.spec.name: p.selected.get() for p in self.panels}
        self.state["debug"] = self.debug.get()
        self.state["parallel"] = self.parallel.get()
        save_state(self.state)
        self.update_start_button()

    def record_success(self, run: Run) -> None:
        runs = self.state.setdefault("runs", {}).setdefault(run.history_key, [])
        runs.append({"duration": run.elapsed(), "steps": run.steps, "milestones": run.milestones})
        del runs[:-HISTORY_RUNS]
        save_state(self.state)


def setup_look(root: tk.Tk) -> None:
    global U
    C.update(PALETTES[system_theme()])
    base = tkfont.nametofont("TkDefaultFont").actual()
    mono = tkfont.nametofont("TkFixedFont").actual()

    def font(source: Any, scale=1.0, weight: Any = "normal") -> tkfont.Font:
        # A negative size is in pixels; scaling keeps the sign.
        return tkfont.Font(root, family=source["family"], size=round(source["size"] * scale), weight=weight)

    F.update(
        title=font(base, 1.6, "bold"), heading=font(base, 1.15, "bold"), body=font(base),
        bold=font(base, weight="bold"), small=font(base, 0.9),
        mono_small=font(mono, 0.9), mono_small_bold=font(mono, 0.9, "bold"),
    )
    U = F["body"].metrics("linespace") // 2


def main() -> None:
    if not DEV_SH.exists():
        sys.exit(f"error: {DEV_SH} not found")
    root = tk.Tk(className="saber-ui-dev")
    setup_look(root)
    App(root)
    root.mainloop()


if __name__ == "__main__":
    main()
