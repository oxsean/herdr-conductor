# Workers by agent

What each kind of worker gets, and what was found testing it. The matrix of runs is in [tests/README.md](../tests/README.md#matrix).

| | Claude Code | Codex CLI | other Herdr agents |
|---|---|---|---|
| start, layout, release | yes | yes | yes |
| brief delivery verified | transcript | rollout transcript | Herdr state only |
| `DONE`, `IDLE`, `BLOCKED`, `GONE`, `HERDR_DOWN`, `UNKNOWN` | yes | yes | yes |
| `STALLED` fingerprint | transcript size | rollout size | screen without its last lines |
| `CHECKIN` from the check-in file | yes | yes | yes |
| `CHECKIN` from a `CHECK-IN:` reply | yes | yes | no |
| `CONTEXT` (tokens) | yes | yes | no |
| `COMPACTED` | yes | yes | no |
| `last.sh` | replies since the last prompt | replies since the last prompt | last lines of the screen |
| resume after `GONE` | `-- --resume <session>` | `-- resume <session>` | agent-specific |
| folder-trust prompt | `spawn.sh --trust` answers it for your own worktrees | none seen | — |

Transcripts are read from `${CLAUDE_CONFIG_DIR:-~/.claude}/projects/*/<session>.jsonl` and `${CODEX_HOME:-~/.codex}/sessions/*/*/*/rollout-*.jsonl`. Both are the agents' own formats, not public contracts: if a release changes them, `doctor.sh` still passes and the events fall back to what Herdr sees; `tests/run.sh checkin` is the quickest way to notice.

## Claude Code

- **Check in by file, not by reply.** Asked to write a plain-text `CHECK-IN:` before editing, Claude workers went straight from reading to tool calls and skipped it: 7 of 8 runs with the brief pasted, 2 of 2 with the brief as a file. Asked to write the design to a check-in file instead, they did, before the first commit, in every run. Codex wrote the plain-text check-in every time and writes the file as well.
- **The brief is a file, the prompt a pointer.** Long pasted text arrives as `<pasted_content id=…>`, which Claude Code marks as possibly not the user's own words; `spawn.sh` sends one short prompt that names the brief file instead.
- `transcript.py` still counts a `<pasted_content>` entry as a prompt; readers that skipped every `<…` entry lost the turn boundary and mixed two turns into one report.
- Herdr reports the session id at start (with `herdr integration install claude`).
- A fast model can write its check-in, finish and stop inside one 30-second poll; the watch then reports `DONE`, and the check-in file is read with the report.

## Codex CLI

- **Swallows input while starting.** Herdr reads the start-up title spinner as `working` and the screen as ready, but a prompt typed then is lost. `spawn.sh` checks that the brief shows up as a prompt in the rollout file and sends it once more only if it did not.
- **A completion before any work.** Codex's `completion_seq` already moves during start-up; `spawn.sh` records the count from just before the brief, so the first `DONE` is the real end of the first turn.
- **Session id arrives late.** Herdr reports it after the first turn; `spawn.sh` finds the rollout file by working directory and start time and notes the id, which `watch.sh` and `last.sh` use until Herdr has it.
- **Stop-and-ask works well.** Given a card that conflicted with a failing test outside its scope, Codex stopped and asked whether to widen the card instead of guessing; asked to check in, it did so before editing in every run.
- Writes in the user's language (from `AGENTS.md`), including full-width punctuation: match questions on `？` as well as `?`.
- Permission mode is yours: Codex started from a shell alias with `--dangerously-bypass-approvals-and-sandbox` runs without prompts; without it, the default sandbox still let workers commit in their worktree in these tests. Prompts it does raise show as `BLOCKED`.

## Choosing kinds per stage

The defaults code with Claude and offer Codex as `second-opinion`. Pointing `roles.review` at Codex gives every branch a reader from a different vendor, which is where the second opinion is worth most; coding with Codex works and is tested, but has had fewer long runs.
