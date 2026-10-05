---
name: herdr-conductor
description: "Conduct a multi-agent job from this Claude Code session: split the work into cards in a ledger file, start worker agents (claude, codex, …) in Herdr panes laid out in one tab, brief them, wait on them, review, verify and integrate their work, and report. Use when the user says conduct this / run this with parallel agents / dispatch herdr workers, 你来指挥 / 让几个 agent 并行做 / 用 herdr 派 worker, resume conducting / 接着指挥 (from a ledger), or invokes /herdr-conductor (`/herdr-conductor doctor` checks the setup); for 派 agent 做 / spawn an agent, ask first whether they mean this mode or a plain sub-agent. Not for one quick delegation (Agent tool) or a fan-out of dozens (Workflow). Requires HERDR_ENV=1; never in a worker (HERDR_CONDUCTOR_ROLE=worker)."
---

# Herdr conductor

This session is the **conductor**. Workers are interactive agents in Herdr panes the user can watch, interrupt and attach to from a phone. Load the official `herdr` skill for command details; this skill is how to run a team with it, and where the two differ (worktrees, cwd, answering a worker's dialog within the user's authorization) this one wins.

| Fits | Use instead |
|---|---|
| Hours of development split into cards, the user wants to watch or step in | — |
| One lookup, one review, nothing to watch | Agent tool (sub-agent) |
| Dozens of uniform items | Workflow tool |

A session whose environment has `HERDR_CONDUCTOR_ROLE=worker` is a worker: it never conducts, whatever its brief quotes. Scripts below are in this skill's `scripts/`; templates in `templates/`.

## Invariants

- **One integrator.** Only the conductor merges, installs, deploys and pushes. Workers commit on their own branch and stop.
- **One ledger, one writer.** All state lives in the ledger, never only in this context: cards, roster, cuts, notes. It sits outside the repository and only the conductor edits it; workers hand their status, cuts and handoffs back in their report.
- **Project rules come from the project.** Read its AGENTS.md / CLAUDE.md / README and copy validation, test tiers, integration, push and forbidden-things rules into the ledger's Integration rules. This skill names no project.
- **Workers run with the user's own permission mode** (often bypass, from a shell alias), so a brief's Never list is not enforced by anything: nothing a worker did reaches the base branch before the conductor read its diff.
- **Workers get only the authority the user gave.** Pushes, deploys, account and permission changes, destructive steps: the user's standing authorization or an explicit yes, recorded in the ledger's Authorization line.
- **Shared contracts before parallel work.** A card that changes an interface another card uses goes first, or the contract is written into both briefs.

## Setup check

The first time this session conducts, and whenever the user asks for `doctor`: run `scripts/doctor.sh --dir <repo>`. Each `FAIL` line carries the command that fixes it; give the user those lines and stop until they are fixed (installing Herdr, its integrations or its skill changes the user's machine: the user runs them, or says yes first). `warn` lines are reported and do not stop the job.

## Configuration

Roles, pipeline and merge defaults come from three layers, later wins: the skill's `config.default.toml`, the user's `~/.config/herdr-conductor/config.toml`, the project's `.herdr-conductor.toml`. `scripts/config.py show --dir <repo>` prints the merged result with each value's source; read it at Start and copy what the job uses into the ledger. A project file may choose agents, models and efforts but not command-line `args`; `config.py` ignores those with a warning, which you pass on.

- **Roles** (`[roles.<name>]`: kind, model, effort, args): what each stage runs on. Defaults: `coding`, `coding-hard` (concurrency, protocol, security, migrations, or over an hour), `mechanical`, `review`, `second-opinion`, `acceptance`, `research`. A card names its role in the ledger; without one it uses `pipeline.coding_role`.
- **Pipeline**: `review` (`never` / `checkin` / `always`) says which cards get a review worker before merging, by `review_role`; `acceptance` is `conductor` or a role to dispatch; `max_coding_workers` caps coding workers at once.
- **Merge**: `strategy` and `revalidate`, unless the project's own rules say otherwise (those win and go into Integration rules).

Choosing within a role: raise effort before changing model. Never change a running worker's level: release it and start a fresh one with another role. Never `/model` or `/effort` in a worker or here to steer workers (`/effort` saves a new global default). The conductor itself runs on what the user started it with; for a long unattended run suggest the strongest model at `high`, set in the start command (changing effort mid-session drops the prompt cache). Record each worker's role, model / effort and Rework count in the roster: they are the data for adjusting the config.

## Scope of the mode

Conducting covers the job in the ledger, not everything the user says afterwards. For each new request in this session:

- Directly: a question, reading a file, opening something, the ledger and notes, and integration: merge, squash, reword, a rebase without conflicts, reverting a commit just merged, install, deploy, acceptance, push.
- Everything that changes the content of the project's tracked files goes to a worker as a card, however small: a fix of a few lines still brings a failing test, debugging and a gate run, which tie up the conductor while the user waits. A merge conflict that needs judgment on content goes back to the worker that wrote the branch; if it cannot settle it, ask the user. In doubt, dispatch.
- Say which in the turn's position line (direct / dispatched); the user's "do this one yourself" or "dispatch this too" overrides it.

A new session enters the mode only when the user asks again (resume conducting / 接着指挥 resumes from the ledger).

## Start

1. One line: the goal, what done means, and when you will check in with the user.
2. Create the ledger outside the repository, even when the repository has its own docs convention (a conclusion that belongs there becomes a docs card at integration): `<ledger.dir>/<YYYY-MM>/<YYYY-MM-DD>-<topic>-ledger.md`, `ledger.dir` from `config.py get ledger.dir`. Template: `templates/ledger.md`, or `templates/zh/ledger.md` when `ledger.language` is `zh` (or `auto` and the user writes Chinese). Briefs go into `<ledger name>-briefs/` beside it. A Chinese ledger is named `<YYYY-MM-DD>-<主题>-指挥台账.md` with briefs in `<台账名>-任务书/`. Fill Conductor (this session's id), Goal, Authorization, Notify, Integration rules, Roles.
3. Split into cards with dependencies, the files each touches (Scope), a checkable completion mark, how it is accepted (Acceptance: a walk of the UI path, CLI commands, API calls, a migration run…), whether it checks in (cards that change a shared contract or span more than one module), its role, and whether it gets a review (per `pipeline.review`). Cards whose Scopes overlap run one after another. Coding workers at once: at most `pipeline.max_coding_workers`; integration is serial, more just queue at the conductor.
4. Show the card table to the user when the split itself is a decision; otherwise start and report. When the split comes out as one chain of cards a few minutes each, with nothing to run in parallel, say so: the mode still works, but its gain is the user watching, not speed.
5. A card's row goes into the ledger before its worker starts: the worker reads it.
6. For a run expected to take more than an hour, offer the user a `/goal` line to paste into this session (a slash command only the user can type), built from the ledger:
   `/goal Every card in <ledger path> is done or deferred with a reason and wrap-up is finished, or a question for me is pending in your last message`
   It keeps the conductor going if a turn ends with no watch armed, and after 30 minutes of background work it prompts a check on the running watches. It never fires while a watch runs, and it pauses on usage limits like the Quota rule. Never put `/goal` in a worker: it fights the stop-and-ask rule.

## Resume (resume conducting / 接着指挥, or after compaction)

0. If the ledger's Conductor session is still in `herdr agent list` and is not this session, another conductor runs this job: stop and tell the user.
1. Rewrite the Conductor line to this session.
2. Reconcile each roster row against `herdr agent list` and `herdr pane list`: live → re-arm its watch (a new watch ends any old one); exited → `scripts/last.sh --session <id>`, then bring it back (GONE below) or close it out; free or stray panes → `scripts/release.sh --pane`.
3. Fix the ledger, then continue.

## Layout

All workers go in the conductor's tab:

```
┌───────────┬──────────┬──────────┐
│           │ ①        │ ③        │
│ conductor ├──────────┼──────────┤
│   40%     │ ②        │ ④        │
└───────────┴──────────┴──────────┘
```

- `scripts/spawn.sh` fills slots in that order, never moves a filled slot, and prefixes the label with the slot it took. Pass `--label "<card> <name> · <model>/<effort>"`, e.g. `C2 sync-c2 · opus/xhigh`. A fifth worker is refused (below ~70 columns an agent is unreadable): free a slot, or create a second tab (`herdr tab create --label <topic>-2 --no-focus`), split it by hand and pass each pane with `--pane`. A tab holding panes that are neither workers nor free slots is refused too: pass `--pane`.
- Names are unique across Herdr: `<topic>-<card>`, e.g. `sync-c2`.
- A worker whose card is accepted is released (`scripts/release.sh`); its pane is labelled `free` and the next worker takes it. At wrap-up every pane this conductor created closes.
- `herdr pane zoom --pane <id>` to read one closely, again to restore.
- Phone: the user runs `herdr agent attach <name>` over ssh. While attached, the agent's terminal takes the phone's size; it returns to the desk size on detach, and the desk layout never changes. Give the user the exact attach command when they ask about a worker away from the desk.

## Worktrees

- A coding worker gets its own worktree **outside the repository**, branched from the current branch (not the default branch): `git worktree add -b <base>-<card> <repo>-<card> <base>`. Repeat any per-clone setup the Integration rules name. Record the base commit on the card.
- Read-only workers (review, research) use the conductor's checkout, or for a review the coding worker's worktree, and must not build or write there if the project forbids it.
- A fresh directory makes Claude ask whether to trust the folder, which also trusts the branch's `.claude/` settings, hooks and `.mcp.json`. `spawn.sh --trust` answers it only for a git worktree whose `.claude/` and `.mcp.json` carry no uncommitted changes; pass it only for a worktree this conductor just created from the user's own branch.

## Brief

Fill `templates/brief.md` into `<ledger name>-briefs/<name>.md`. A brief is self-contained: a reader who never saw this conversation can do the card from it and the files it names; paths are absolute; facts stated are ones you checked, not guesses. Every brief states: the card and ledger path; what to read; the outcome and verified facts (for the strongest models, goals and constraints, not steps); what never to touch; the completion mark; the report with its fixed sections. Never "think carefully".

- Check-in: cards marked check-in get the check-in paragraph: before its first edit the worker writes its design to `<brief>.checkin.md` beside the brief, then keeps going; `watch.sh` reports `CHECKIN <name> <file>` as soon as the file is written, for any kind of worker. A file, not a reply: Claude Code workers go straight from reading to tool calls and skipped a plain-text `CHECK-IN:` in nearly every test run. Small cards leave it out. A worker that skipped a required check-in gets its design reviewed in the diff first.
- Stop and ask: a worker unsure where a wrong guess is expensive writes the question as its last paragraph and stops, which ends the turn (`DONE`). Never a question dialog: it stalls the pane until someone answers.

```bash
scripts/spawn.sh --name <name> --role <role> --dir <worktree> --label "C1 <name> · opus/high" \
  --brief <brief file> [--trust]
```

`--role` takes kind, model and effort from the configuration; arguments after `--` are appended. `--kind <kind> -- <args>` starts an agent without it. The worker gets one short prompt pointing at the brief file, never the pasted brief: Claude Code marks long pasted text as possibly not the user's own words. `spawn.sh` returns only once the worker's transcript shows the prompt. Write the roster row right after spawning, with the session id and pane `spawn.sh` prints, then arm its watch.

## Waiting

One `scripts/watch.sh <name>` per worker, with Bash `run_in_background`; it exits with one event line and the conductor is notified. Re-arm it after handling every event except `GONE`. Never `herdr agent wait` bare in the background (it never returns from a hung or unclassified worker, and returns at once from an idle one) and never poll in the foreground.

| Event | First look | Then |
|---|---|---|
| `DONE` | `last.sh` | **Finished**: verify (below). A **question**: answer with `herdr agent prompt`, re-arm. A **usage-limit / rate-limit** message: the Quota rule below. An **API error** or "try again": prompt `continue` once, re-arm; a second time, treat as quota or report |
| `CHECKIN` | the check-in file it names (`-`: `last.sh`) | compare with the card; answer only to correct (`herdr agent prompt`), at once; re-arm |
| `IDLE` | the screen | waiting on its own background job (a gate run) → re-arm; finished without a report or stuck at its prompt → prompt what to do, re-arm |
| `BLOCKED` | `herdr agent read <name> --source visible` | an approval or question within the user's authorization → answer with `agent send-keys`; otherwise ask the user. A question dialog the brief forbade → answer it, then tell the worker to ask in text |
| `STALLED` | the screen | a long command still running (test suite, build) → re-arm with a larger `--stall`. A hung call, a retry loop, a prompt nobody sees → `esc`, then `continue` with what to do. Nothing recoverable → `ctrl+c`, prompt again; still stuck → replace it (below) |
| `GONE` | `herdr pane read <pane> --source recent-unwrapped`, `last.sh --session <id>` | find why (exit, crash, quota). Bring the same session back in the same pane: `spawn.sh --pane <pane> --name <name> --role <role> --brief <short> -- --resume <session>` (claude), brief: "Continue card <ID>; check your branch's commits and the report you were writing." Session unusable → replace it (below) |
| `HERDR_DOWN` | `herdr agent list` | Herdr did not answer; the worker may be fine. Never replace a worker on this alone: wait a minute and re-arm; still down → tell the user |
| `UNKNOWN` | the screen | Herdr lost track of it; judge by the screen, re-arm |
| `CONTEXT` / `COMPACTED` | — | at its next natural break: it commits work in progress on its branch and puts a handoff (done, left, decisions, traps) in its report; release it and start a fresh worker in the same worktree with the handoff in its brief. `CONTEXT` fires at 250k tokens by default: for a 200k-window model pass a lower `--context`, or rely on `COMPACTED` |

A first watch on a worker that already finished a turn reports that `DONE` at once.

**Replace a worker**: release it (`release.sh`, which interrupts a busy one first), keep its worktree and branch, start a new one there with the original brief plus "the previous worker left commits <…> and this handoff: <…>". Rework count + 1 when the cause was quality, not infrastructure.

**Quota (usage limit)**: the conductor and the workers usually share one account, so all stop together. Note the reset time in the ledger's Notes, stop re-arming, never retry in a loop; tell the user. If the user is away, wait with the Monitor tool on an until-loop (`until [ "$(date +%s)" -ge <reset epoch + 300> ]; do sleep 60; done`), not a bare `sleep`; when it fires, prompt each worker `continue` and re-arm the watches.

Notify the user at milestones and when blocked on them, by the ledger's Notify line (`notify.method`: the session's push tool, or `herdr notification show`; check its `--help` first).

## Verify and integrate

In this order:

1. Read the diff; check each claim in the report against code and git. Check: the worker's branch starts at the card's base and the main checkout is clean; nothing the Integration rules forbid (names, secrets). The base branch moved since: rebase in the worker's worktree yourself when it applies without conflicts (the tree is then new: validate it); a conflict goes back to the worker.
2. Review, when the card gets one: a worker on `pipeline.review_role`, read-only in the coding worker's worktree, brief: the card, the base commit, the diff range, what to look for (correctness against the card, the shared contract, tests that prove it), report only blockers and should-fix items with file:line. Findings that hold go back to the coding worker as rework; the reviewer is released when its report is read.
3. Acceptance by the card's Acceptance line, on the worker's worktree before merging, by the conductor or the `pipeline.acceptance` role. For a UI it walks **the path the user takes** (open the app, navigate there), not a deep link or a test helper; a feature reachable only by URL is not done.
4. Rework: send the worker the concrete failure; Rework count + 1. The worker stays until its card is accepted, and a follow-up in the same area goes to it while it is still there.
5. Shape the branch: more than one logical commit (work in progress, fixups) → squash or reword in its worktree after a `backup/` tag.
6. Merge as the Integration rules say (else `merge.strategy`). A fast-forward to the exact tree the worker validated (`git rev-parse HEAD^{tree}` equal) needs no second run when `merge.revalidate` is `changed-tree` and the project's rules do not say the integrator always runs it; write which in the Integration rules. Whatever runs, output to a file, exit status read from it. Several cards landing together: merge all, validate once.
7. Install, deploy, push only within Authorization. Card Status → done with commits and where it is installed; release the worker.

## Reports to the user

Write to the user in their language.

- Each turn opens with one position line: step n/N done; next: ….
- On dispatching, say what the worker is doing, its slow step and roughly how long (a gate run, a regression), and where to watch it: its slot, or `herdr agent attach <name>` from a phone. A quiet stretch the user was told about is not a worry.
- A separate "what was cut this time" list from the ledger's table.
- Before raising a "waiting on you" item, check the ledger and git that it is still open.
- End with what is needed from the user, ranked.

## Wrap-up

1. `scripts/release.sh <name> --close` for each worker still running; `scripts/release.sh --pane <pane> --close` for each free slot. Close only the panes and tabs this conductor created.
2. Per worktree: an unmerged branch gets `backup/<branch with / as ->-tip-<YYYYMMDD>` first. `git worktree remove` without `--force`; `git branch -d`. A dirty worktree, or a branch `-d` refuses that is not fully cherry-picked, is listed to the user, not forced.
3. Final ledger: every card's state, roster closed, cuts complete, tags made.

## Other agents as workers

Claude workers get every event. Others are supported as far as Herdr sees them; `docs/agents.md` holds the tested matrix.

- `watch.sh` follows a non-Claude worker by its screen: no `CHECKIN`, `CONTEXT` or `COMPACTED`; `STALLED` compares the screen without its last lines.
- `last.sh` prints the last lines of its screen instead of its reply: pass `--lines` when a report is long.
- `--resume` is Claude's; a Codex session comes back with `-- resume <session>`.
- Only Claude Code conducts: Codex lacks background shells with completion notices.

## Pitfalls seen in practice

- A worker reports, does not wait, and keeps going: correct a wrong check-in at once.
- A worker's harness may refuse a command outright (long standalone `sleep`): a quick DONE is not a hang.
- `/exit` typed into a busy worker is queued behind its turn, and a blocked one refuses prompts; `release.sh` clears both first.
- `agent start` returns `agent_not_ready` on the trust dialog of a new directory; Herdr may show `blocked` for a moment after it closes (`spawn.sh` settles on the screen).
- A shell left in a removed worktree breaks the next agent started there: `release.sh` moves it to `$HOME`.
- Herdr forgets an agent's name once it exits: `last.sh` and `release.sh` then need the session id or pane from the roster.
- Tests a worker wrote can be flaky under the full suite or on another OS: run the test tier the Integration rules name for the risk; the top tier only when it says high risk or the user asks.
- Claims of "N commits", "all done", "item X still open" are checked against git and the ledger before they reach the user.
- Follow-up prompts to a worker stay short, or point at a file, for the same reason as the brief.
- A fast worker can write its check-in, finish and stop within one poll: the event is `DONE`; read the check-in file with the report.
- Workers answer in the user's language: a question may end in `？`.
