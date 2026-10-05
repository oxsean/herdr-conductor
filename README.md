# herdr-conductor

**One Claude Code session conducts a team of coding agents in [Herdr](https://herdr.dev) panes.** You see every worker live, step in from your desk or your phone, and nothing reaches your branch until the conductor has read the diff.

[中文说明](README.zh-CN.md)

```
┌───────────────────┬──────────────────────┬──────────────────────┐
│                   │ ① C1 auth · opus/high│ ③ C3 docs · sonnet   │
│  conductor        │   CHECK-IN: …        │   DONE ✓             │
│  (Claude Code)    ├──────────────────────┼──────────────────────┤
│  ledger · events  │ ② C2 api · codex     │ ④ review · fable     │
│  review · merge   │   running tests…     │   2 should-fix       │
└───────────────────┴──────────────────────┴──────────────────────┘
```

## Why

A sub-agent works out of sight and hands back a summary. A workflow fans out dozens of identical items. Real development is neither: a few hours of work split into cards, where you want to **watch** the workers, **answer** them when they ask, and **trust** what lands on your branch.

herdr-conductor is a Claude Code skill (shipped as a plugin) that turns one session into a conductor:

- **Cards in a ledger.** The job is split into cards with scope, dependencies, a done mark and an acceptance method, written to a Markdown ledger outside the repository. The ledger, not the context window, holds the state: a compacted or new session resumes from it.
- **One worktree per worker.** Each coding worker gets its own git worktree and branch, in a fixed 2×2 grid beside the conductor. Claude Code and Codex workers side by side.
- **Event-driven waiting.** One background watch per worker reports `DONE`, `CHECKIN`, `BLOCKED`, `STALLED`, `CONTEXT`, `GONE`… from Herdr's state and the worker's own transcript. No polling, no `sleep` loops.
- **Stages you configure.** Which agent, model and effort codes, reviews and accepts, and when review is required, comes from a TOML file per user or per project.
- **One integrator.** Workers commit on their branch and stop. Only the conductor reviews the diff, runs acceptance, merges, installs and pushes, and only within what you authorized.

## Install

Order matters: each step needs the one before it.

| Step | Command | Why |
|---|---|---|
| 1. Herdr | `curl -fsSL https://herdr.dev/install.sh \| sh` (or `brew install herdr`), then run `herdr` once | the terminal multiplexer the workers live in |
| 2. Herdr integrations | `herdr integration install claude` (and `codex` for Codex workers) | Herdr learns each agent's session id: needed to resume a worker and read its transcript |
| 3. Official herdr skill | `npx skills add herdrdev/herdr --skill herdr -g -a claude-code` | teaches Claude Code the `herdr` CLI; this skill builds on it. Without npx: `herdr --skill > ~/.claude/skills/herdr/SKILL.md` |
| 4. This plugin | `claude plugin marketplace add oxsean/herdr-conductor`<br>`claude plugin install herdr-conductor@herdr-conductor` | the conductor itself (or, inside Claude Code, `/plugin marketplace add …` and `/plugin install …`) |
| 5. Check | in Claude Code, inside a Herdr pane: `/herdr-conductor:herdr-conductor doctor` | lists anything missing, each with the command that fixes it |

Or steps 2–5 in one go, confirming each change: `git clone https://github.com/oxsean/herdr-conductor && herdr-conductor/install.sh --codex`.

Requirements: Herdr 0.9.3+, Claude Code 2.1.236+ (for `/goal`), Python 3.11+, git. Codex CLI optional. macOS and Linux.

## Use

1. Run `herdr`, open a pane in your repository and start the conductor: `claude --model opus --effort high`.
2. Say what you want: *"Conduct this: add rate limiting to the API and a settings page for it. You may not push."*
   The conductor checks the setup, reads the project's own rules (AGENTS.md / CLAUDE.md / README), writes the ledger, shows the cards when the split is a decision, and starts workers in the panes to its right.
3. For a run longer than an hour, paste the `/goal` line it offers (see below).
4. Watch any pane; click into one to talk to that worker. Away from the desk: `ssh <mac> herdr agent attach <worker>`.
5. After a break or a compaction: *"resume conducting ~/…/2026-10-05-rate-limit-ledger.md"*.

Each turn of the conductor opens with where it is (step n/N done; next: …) and ends with what it needs from you, ranked.

### Pair it with `/goal`

Claude Code's [`/goal`](https://code.claude.com/docs/en/goal.md) keeps a session working until a condition holds. The conductor offers one built from its ledger:

```
/goal Every card in ~/…/rate-limit-ledger.md is done or deferred with a reason and wrap-up is finished, or a question for me is pending in your last message
```

The two cover each other: the watches wake the conductor on every worker event, and `/goal` catches a turn that ends with no watch armed, and after 30 minutes of background work it prompts a check on the running watches. It pauses on usage limits instead of retrying. Use it in the conductor only: a worker under `/goal` cannot stop to ask a question.

## Configure the stages

`~/.config/herdr-conductor/config.toml` (yours) and `<repo>/.herdr-conductor.toml` (the project's) override [the defaults](skills/herdr-conductor/config.default.toml):

```toml
[roles.coding]
kind = "claude"
model = "opus"
effort = "high"

[roles.review]                 # a different vendor reads every branch
kind = "codex"                 # model left empty: your Codex default
effort = "high"

[pipeline]
review = "always"              # never | checkin | always
review_role = "review"
acceptance = "conductor"       # or a role name to dispatch an acceptance worker
max_coding_workers = 3

[merge]
strategy = "squash"
```

A project file may pick agents, models and efforts but never command-line `args`, which could switch off a worker's sandbox. See [docs/configuration.md](docs/configuration.md); `scripts/config.py show --dir <repo>` prints the merged result with each value's source.

## Agents

| Worker | Status | Notes |
|---|---|---|
| Claude Code | supported | every event; `--resume` after a crash |
| Codex CLI | supported, newer | events from its rollout transcript; brief delivery verified; see [docs/agents.md](docs/agents.md) |
| other Herdr agents | untested | screen-only: `DONE`, `BLOCKED`, `STALLED`, `IDLE`, `GONE` |

Only Claude Code conducts: it is the one with background shells that notify on exit.

## Safety model

- Workers run with **your** permission mode. If your shell alias adds `--dangerously-skip-permissions`, so do they; a brief's "never" list is guidance, not a sandbox. What protects your branch is that only the conductor merges, after reading the diff.
- Pushes, deploys, account or permission changes and destructive steps need your standing authorization or an explicit yes, written into the ledger's Authorization line.
- `spawn.sh --trust` answers Claude's folder-trust prompt only for a git worktree whose `.claude/` and `.mcp.json` are committed and unchanged, i.e. your own branch's settings.
- Project config cannot add command-line arguments.

## Repository

```
skills/herdr-conductor/      the skill: SKILL.md, scripts/, templates/, config.default.toml
  scripts/spawn.sh           start a worker in the next grid slot and hand it its brief
  scripts/watch.sh           wait on one worker, exit with one event line
  scripts/last.sh            what a worker said last (from its transcript)
  scripts/release.sh         end a worker, free or close its pane
  scripts/doctor.sh          setup check
  scripts/config.py          merged configuration
  scripts/transcript.py      Claude Code and Codex transcript reader
tests/                       scenario runner for the scripts against real workers
docs/                        configuration, agents, design notes
install.sh                   steps 2–5 above
```

## Tests

`tests/run.sh <scenario> --role <role>` starts a real worker in its own Herdr tab on a throwaway repository and checks what it did. See [tests/README.md](tests/README.md) for the scenarios and the latest matrix.

## License

MIT. Herdr is a separate project by its authors under Apache-2.0; this repository does not include it.
