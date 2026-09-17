# Agent dashboard

Live terminal view of LandTracker's Claude Code subagents, for when several are running at once.

## Run it

Two terminals (or two `tmux`/split panes), both `cd`'d into the project root:

**Terminal 1 — the dashboard itself, leave it running:**
```
uv run .claude/dashboard/dashboard.py
```

**Terminal 2 (and 3, 4...) — launch an agent through the wrapper instead of calling `claude` directly:**
```
.claude/dashboard/run-agent.sh security-engineer "review RLS policies on the new IoT table"
```

Each launch shows up as a row in the dashboard the moment it starts, and updates live (status, elapsed time, last log line) until it finishes.

## How it works
- `run-agent.sh` runs `claude -p "<prompt>" --agent <name>` headlessly, writes a status JSON to `status/` before and after, and the full transcript to `logs/`.
- `dashboard.py` polls `status/*.json` once a second and renders a live `rich` table. Needs `uv` (already installed at `~/.local/bin`) — it reads the dependency header at the top of the script and provisions `rich` automatically, nothing to install by hand.
- `status/` and `logs/` are gitignored — they're runtime state, not config. Only `dashboard.py`, `run-agent.sh`, and this README are committed.

`dashboard.py --once` prints a single snapshot and exits, instead of the live loop — useful for scripting/testing.
