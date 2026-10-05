# Design notes

Why the skill is shaped the way it is. Each rule here came from a run that went wrong without it.

## One integrator

Workers run with the user's permission mode, often a bypass alias. A brief's "never push" is text, not a sandbox. The guarantee the user actually gets is structural: workers commit on their own branch in their own worktree, and only the conductor merges, after reading the diff and running acceptance. Everything else (review stage, `backup/` tags before rewrites, `git worktree remove` without `--force`) follows from keeping that one door narrow.

## The ledger is the state

A conductor runs for hours. Its context will be compacted, or the user will close the terminal and come back tomorrow. So every decision lives in a Markdown file outside the repository: cards, roster with session ids and panes, cuts, authorization, notes. A new session told "resume conducting <ledger>" reconciles the roster against `herdr agent list` and carries on. Only the conductor writes the ledger; workers report, the conductor copies. Two writers would race and nobody could tell which line is true.

## Why two or three coding workers, not ten

Integration is serial: read the diff, review, accept, merge, validate. With more than three coding workers the queue forms at the conductor, and the user's attention is the real bottleneck. The 2×2 grid is the visual form of that limit: beyond four panes an agent is unreadable on a laptop screen.

## Waiting without polling

`herdr agent wait` alone is the wrong primitive: it returns at once from an idle agent and never from a hung one. `watch.sh` is one background process per worker that exits with exactly one event line, which wakes the conductor through Claude Code's background-shell notification. It combines:

- Herdr's state (`working`, `idle`, `done`, `blocked`) and its `completion_seq`, so a turn that ends between two polls is still reported once;
- the worker's own transcript (Claude Code's project JSONL, Codex's rollout file) for `CHECKIN`, `CONTEXT` and `COMPACTED`, and as the progress fingerprint behind `STALLED`, because a terminal's spinners change while nothing happens;
- a re-arm after every event, so each event is handled before the next is looked for.

## Check in, but don't wait

A worker on a card that changes a shared contract writes `CHECK-IN:` with its design, then keeps going. Waiting for approval would idle the worker for as long as the conductor is busy with another; correcting a wrong design a minute in is cheap. Small cards skip it.

## Ask in text, never in a dialog

A question dialog freezes the pane until someone presses a key, and on a phone that someone is not watching. A worker unsure where a wrong guess is expensive writes the question as its last paragraph and stops; the turn ends, `watch.sh` reports `DONE`, the conductor answers with a prompt. This is also why `/goal` belongs in the conductor and never in a worker: a goal keeps the worker from stopping.

## Delivery is proven by the transcript

Herdr's state is a classification of the screen. Codex sets a spinning terminal title while it starts, which reads as `working`, and swallows input typed before it is ready. `spawn.sh` therefore checks that the brief appears as a new prompt in the worker's transcript before it reports success, sends it once more only when it did not, and records the completion count from just before the brief so a start-up "completion" is never reported as `DONE`.

## Configuration has a trust boundary

Roles are configurable per user and per project, but a project file — which arrives with `git clone` — may only choose agent, model and effort, never command-line arguments.

## What the conductor does itself

Questions, reading, the ledger and integration (merge, squash, rebase without conflicts, install, deploy, acceptance, push). Anything that changes the project's tracked files is a card for a worker, however small: a three-line fix still brings a failing test, debugging and a gate run, and while the conductor does it, no one answers the workers.
