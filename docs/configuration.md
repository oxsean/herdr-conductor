# Configuration

Three TOML layers, merged key by key, later wins:

1. `skills/herdr-conductor/config.default.toml` — built in.
2. `~/.config/herdr-conductor/config.toml` — yours (`$HERDR_CONDUCTOR_CONFIG` or `$XDG_CONFIG_HOME` move it).
3. `<repo>/.herdr-conductor.toml` — the project's, committed with it.

```bash
scripts/config.py show --dir <repo>       # every value and the file it came from
scripts/config.py agent review --dir <repo>   # the kind, then the arguments spawn.sh will pass
```

The conductor reads the merged config at Start and copies what the job uses into the ledger's Roles section, so a run keeps its settings even if a file changes mid-job.

## `[roles.<name>]`

A role is the agent a stage of a card runs on.

| Key | Meaning |
|---|---|
| `kind` | any agent Herdr can start: `claude`, `codex`, … |
| `model` | `claude --model <model>` / `codex -m <model>`; empty = the agent's own default |
| `effort` | `claude --effort` (`low` `medium` `high` `xhigh` `max`) / `codex -c model_reasoning_effort=` (`minimal` `low` `medium` `high` `xhigh`) |
| `args` | extra command-line arguments, **user file only** |

Built-in roles: `coding`, `coding-hard`, `mechanical`, `review`, `second-opinion`, `acceptance`, `research`. Add your own (`[roles.frontend]`) and name it on a card.

`spawn.sh --role <name>` resolves a role; arguments after `--` are appended (`-- --resume <session>`).

## `[pipeline]`

| Key | Values | Meaning |
|---|---|---|
| `coding_role` | a role | who writes code for a card that names no role |
| `review` | `never` · `checkin` · `always` | which cards get a review worker before merging; `checkin` = cards marked check-in (shared contracts, more than one module) |
| `review_role` | a role | who reviews |
| `acceptance` | `conductor` · a role | who runs a card's acceptance |
| `max_coding_workers` | number | coding workers at once; integration is serial, more only queue |

## `[merge]`

| Key | Values | Meaning |
|---|---|---|
| `strategy` | `ff` · `squash` · `rebase` · `cherry-pick` | how an accepted branch lands |
| `revalidate` | `always` · `changed-tree` | re-run validation after merging, or skip it when the merged tree equals the tree the worker validated |

A project's own written rules (AGENTS.md, CLAUDE.md, CONTRIBUTING) win over `[merge]`; the conductor copies them into the ledger's Integration rules.

## `[ledger]` and `[notify]`

| Key | Default | Meaning |
|---|---|---|
| `ledger.dir` | `~/.local/share/herdr-conductor/ledgers` | ledgers go to `<dir>/<YYYY-MM>/`, always outside the repository |
| `ledger.language` | `auto` | `en`, `zh`, or the language you write in |
| `notify.method` | `push` | `push` (the session's push tool), `herdr` (`herdr notification`), `none` |

## Why a project file cannot set `args`

A project file arrives with `git clone`. If it could add arguments, a repository could start your workers with `--dangerously-bypass-approvals-and-sandbox` or an MCP server of its choosing. It may choose the agent, the model and the effort; `config.py` drops `args` from it with a warning the conductor passes on.

## Examples

A team that wants a second vendor on every review and squashed merges, in `.herdr-conductor.toml`:

```toml
[roles.review]
kind = "codex"
effort = "high"

[pipeline]
review = "always"

[merge]
strategy = "squash"
```

A user who keeps ledgers with their notes, writes Chinese, and starts Codex with a fixed model, in `~/.config/herdr-conductor/config.toml`:

```toml
[ledger]
dir = "~/Documents/notes"
language = "zh"

[roles.second-opinion]
kind = "codex"
model = "<your codex model>"
effort = "xhigh"
args = ["-c", "mcp_servers.node_repl.enabled=false"]
```
