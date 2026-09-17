# Session reports

Written by the `docs-writer` agent once per session (or once per production-line run), never mid-session.

**Filename:** `YYYY-MM-DD-<short-slug>.md` — date the session ended, slug is a few words on the main thing done (e.g. `2026-09-17-security-agent-semgrep.md`).

**Contents:**
- What changed (bullet list, grounded in the actual diff/commits — not assumed intent)
- Why (only if stated by the user or evident from commit messages; skip if unknown rather than guessing)
- Any doc drift found and fixed in `CLAUDE.md` / `PRODUCT.md`, if applicable
- Open threads / follow-ups mentioned but not done in this session

Sessions with no doc-relevant changes don't need an entry.
