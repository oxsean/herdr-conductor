# Changelog

## 0.1.0 — unreleased

First public release.

- Conductor skill: cards in a ledger, one worktree per worker, 2×2 pane grid, event-driven watches, review, acceptance, single integrator, resume from the ledger.
- Roles, pipeline and merge settings from TOML (built-in, user, project); `spawn.sh --role`.
- Codex workers: brief delivery checked against the rollout transcript; `CHECKIN`, `CONTEXT`, `COMPACTED` and `last.sh` from the transcript; resume with `-- resume <session>`.
- `doctor.sh` setup check; `install.sh` for integrations, the official herdr skill and the plugin.
- `tests/run.sh` scenarios against real Claude Code and Codex workers.
- English and Chinese ledger templates.

Tested with Herdr 0.9.3, Claude Code 2.1.289, Codex CLI 0.155.1 on macOS.
