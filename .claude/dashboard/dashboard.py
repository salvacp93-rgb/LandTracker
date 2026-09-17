# /// script
# dependencies = ["rich"]
# ///
"""Live terminal dashboard for LandTracker's Claude Code subagents.

Run with: uv run .claude/dashboard/dashboard.py
(uv reads the dependency block above and provisions `rich` automatically —
nothing to install by hand.)

Reads .claude/dashboard/status/*.json, written by run-agent.sh, and renders
a live-refreshing table. Pass --once to print a single snapshot and exit
(used for scripting/testing rather than the live view).
"""
import glob
import json
import os
import sys
import time

from rich.console import Console
from rich.live import Live
from rich.table import Table

CORAL = "rgb(204,120,92)"  # Anthropic-ish clay/coral accent
STATUS_COLORS = {"running": "yellow", "done": "green", "failed": "red"}
STATUS_ICON = {"running": "●", "done": "✓", "failed": "✗"}

DASH_DIR = os.path.dirname(os.path.abspath(__file__))
STATUS_DIR = os.path.join(DASH_DIR, "status")


def load_statuses():
    rows = []
    for path in sorted(
        glob.glob(os.path.join(STATUS_DIR, "*.json")),
        key=os.path.getmtime,
        reverse=True,
    ):
        try:
            with open(path) as f:
                rows.append(json.load(f))
        except (json.JSONDecodeError, OSError):
            continue
    return rows


def tail_line(log_path):
    try:
        with open(log_path, "rb") as f:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            f.seek(-min(size, 4000), os.SEEK_END)
            lines = [l for l in f.read().decode(errors="ignore").splitlines() if l.strip()]
            return lines[-1].strip() if lines else ""
    except OSError:
        return ""


def build_table():
    table = Table(
        title="LandTracker — Agent Dashboard",
        title_style=f"bold {CORAL}",
        border_style=CORAL,
        header_style=f"bold {CORAL}",
        expand=True,
    )
    table.add_column("Agent", style="bold")
    table.add_column("Status")
    table.add_column("Elapsed")
    table.add_column("Task", overflow="ellipsis", no_wrap=True, max_width=40)
    table.add_column("Last output", overflow="ellipsis", no_wrap=True)

    rows = load_statuses()
    if not rows:
        table.add_row("—", "[dim]no runs yet[/dim]", "", "", "")
        return table

    now = time.time()
    for r in rows:
        status = r.get("status", "unknown")
        color = STATUS_COLORS.get(status, "white")
        icon = STATUS_ICON.get(status, "?")
        started = r.get("started_at", now)
        ended = r.get("ended_at")
        elapsed = (ended or now) - started
        mins, secs = divmod(int(elapsed), 60)
        last_line = tail_line(r.get("log_path", "")) if status == "running" else ""
        table.add_row(
            r.get("agent", "?"),
            f"[{color}]{icon} {status}[/{color}]",
            f"{mins}m{secs:02d}s",
            r.get("task", ""),
            last_line,
        )
    return table


def main():
    console = Console()
    if "--once" in sys.argv:
        console.print(build_table())
        return
    with Live(build_table(), console=console, refresh_per_second=1) as live:
        while True:
            time.sleep(1)
            live.update(build_table())


if __name__ == "__main__":
    main()
