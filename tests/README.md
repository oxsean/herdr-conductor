# Tests

The scripts are tested against **real workers**: `run.sh` drives `spawn.sh`, `watch.sh`, `last.sh` and `release.sh` in the order the skill uses them, with no conductor model in the loop, then checks what the worker did. A run costs a few minutes and a small amount of model usage.

```bash
tests/run.sh fix-bug --role coding                          # a configured role
tests/run.sh checkin --kind codex -- -c model_reasoning_effort=medium
tests/run.sh fix-bug --role mechanical --plain-shell        # without your shell profile and aliases
```

Run it from a Herdr pane. Each run creates its own tab and a throwaway copy of `fixtures/calc` under `$TMPDIR`, closes the tab when done, and keeps the run directory (brief, events, report, screen, checks) when it fails or with `--keep`. Runs can go in parallel.

## Scenarios

| Scenario | The card | What is checked |
|---|---|---|
| `fix-bug` | fix a failing test in `calc.py` | brief delivered once; `DONE` only after the real turn; a commit on the branch, tests pass, nothing outside the card's scope, main checkout untouched, report sections present |
| `checkin` | add `parse_price` across two modules, marked check-in | a `CHECK-IN:` design in the worker's own replies; `watch.sh` raised `CHECKIN` (or the whole turn fit in one poll); then the same as `fix-bug` |
| `ask-and-stop` | rename a public function whose new name only the owner knows | first turn: a question in text, no commits, no dialog; after the runner answers: the rename landed under that name |

A scenario is a directory with `card.md` (the card, placed into a standard brief), `check.sh` (sources `lib/checks.sh`), and optionally `prepare.sh` (runs in the fresh fixture before its first commit), `answer.txt` and `first-done.sh` (the answer to send after the first `DONE`, and the checks before sending it).

## Matrix

Herdr 0.9.3 · Claude Code 2.1.289 · Codex CLI 0.155.1 · macOS · 2026-10-05.

`tests/matrix.sh`, final run (`--role coding` = Claude opus/high, `--role mechanical` = Claude sonnet/medium):

| Scenario | `--role coding` | `--role mechanical` | `--kind codex -- -c model_reasoning_effort=medium` |
|---|---|---|---|
| ask-and-stop | PASS · <1m · DONE, DONE | PASS · <1m · DONE, DONE | PASS · 1m · DONE, DONE |
| checkin | PASS · 1m · CHECKIN, DONE | PASS · <1m · CHECKIN, DONE | PASS · 1m · CHECKIN, DONE |
| fix-bug | PASS · <1m · DONE | PASS · <1m · DONE | PASS · 1m · DONE |

Also passed: `fix-bug --plain-shell` for Claude (sonnet, the user's settings in `auto` mode) and Codex (no bypass alias).

Found and fixed on the way to this table: Codex swallowing the first prompt and reporting a start-up completion; Claude's `<pasted_content>` wrapping breaking turn boundaries; a race starting an agent in a pane whose shell was still starting; Claude workers skipping a plain-text check-in (now a file).

Run it yourself with `tests/matrix.sh` (about 10 minutes, 3 at a time).

## Not covered here

- The conductor model's own behaviour (splitting cards, judging a diff, integration): that needs a conductor session and is checked by hand on real jobs.
- `GONE` and resume: checked by hand (Codex `-- resume <session>` brought back a session that recalled its previous reply).
- `STALLED`, `CONTEXT`, `COMPACTED`: need long or stuck runs.
