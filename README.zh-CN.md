# herdr-conductor

**一个 Claude Code 会话，在 [Herdr](https://herdr.dev) 的格子里指挥一整队编码 agent。** 每个 worker 在干什么都看得见，坐在桌前或拿起手机都能插手；主控没读过的 diff，进不了你的分支。

[English](README.md)

```
┌───────────────────┬──────────────────────┬──────────────────────┐
│                   │ ① C1 auth · opus/high│ ③ C3 docs · sonnet   │
│  主控              │   CHECK-IN: …        │   DONE ✓             │
│  (Claude Code)    ├──────────────────────┼──────────────────────┤
│  台账 · 事件       │ ② C2 api · codex     │ ④ review · fable     │
│  评审 · 合并       │   跑测试中…           │   2 条 should-fix     │
└───────────────────┴──────────────────────┴──────────────────────┘
```

## 为什么要它

sub-agent 在暗处干活，最后交回一段总结；Workflow 适合几十个一模一样的小活。真实的开发两样都不是：几个小时的活拆成几张卡，你想**看着** worker 干，它问你时能**回答**，落到分支上的东西你能**信得过**。

herdr-conductor 是一个 Claude Code skill（以 plugin 形式发布），把一个会话变成主控：

- **卡片进台账。** 活拆成卡片，每张写清改动范围、依赖、完成标志和验收方式，记在仓库外的 Markdown 台账里。状态在台账里，不在上下文里：上下文被压缩、换一个会话，都能从台账接着干。
- **一个 worker 一棵 worktree。** 每个写代码的 worker 有自己的 git worktree 和分支，固定排在主控右边的 2×2 格子里。Claude Code 和 Codex 可以并排。
- **事件驱动的等待。** 每个 worker 一个后台 watch，从 Herdr 的状态和 worker 自己的 transcript 里报 `DONE`、`CHECKIN`、`BLOCKED`、`STALLED`、`CONTEXT`、`GONE`……不轮询，不 `sleep`。
- **每个环节用谁，可以配置。** 写代码、评审、验收各用哪个 agent、模型和 effort，什么卡必须评审，都写在用户级或项目级的 TOML 里。
- **只有一个集成者。** worker 在自己的分支上提交就停下。只有主控读 diff、评审、验收、合并、装机、推送，而且只在你授权的范围内。

## 安装

顺序不能乱，每一步都依赖上一步。

| 步骤 | 命令 | 为什么 |
|---|---|---|
| 1. Herdr | `curl -fsSL https://herdr.dev/install.sh \| sh`（或 `brew install herdr`），然后运行一次 `herdr` | worker 住在它的格子里 |
| 2. Herdr 的 agent 集成 | `herdr integration install claude`（用 Codex worker 再加 `codex`） | Herdr 由此拿到每个 agent 的会话 id：恢复 worker、读它的 transcript 都靠它 |
| 3. Herdr 官方 skill | `npx skills add herdrdev/herdr --skill herdr -g -a claude-code` | 教 Claude Code 用 `herdr` 命令行，本 skill 建在它上面。没有 npx：`herdr --skill > ~/.claude/skills/herdr/SKILL.md` |
| 4. 本 plugin | `claude plugin marketplace add oxsean/herdr-conductor`<br>`claude plugin install herdr-conductor@herdr-conductor` | 主控本身（也可以在 Claude Code 里用 `/plugin marketplace add …`、`/plugin install …`） |
| 5. 自检 | 在 Herdr 格子里的 Claude Code 中：`/herdr-conductor:herdr-conductor doctor` | 列出缺什么，每条附上修复命令 |

也可以一次做完第 2–5 步，每处改动都会先问你：`git clone https://github.com/oxsean/herdr-conductor && herdr-conductor/install.sh --codex`。

依赖：Herdr 0.9.3+、Claude Code 2.1.236+（`/goal` 需要）、Python 3.11+、git；Codex CLI 可选。支持 macOS 和 Linux。

## 使用

1. 运行 `herdr`，在仓库里开一个格子，启动主控：`claude --model opus --effort high`。
2. 说你要什么：「你来指挥：给 API 加限流，再做一个设置页。不许推送。」
   主控会先自检，读项目自己的规矩（AGENTS.md / CLAUDE.md / README），写台账；拆分本身需要你拍板时先给你看卡片表，然后在右边的格子里启动 worker。
3. 预计超过一小时的活，把主控给你的 `/goal` 那一行贴进去（见下）。
4. 看任意一个格子；点进去就能直接跟那个 worker 说话。不在桌前：`ssh <mac> herdr agent attach <worker>`。
5. 歇一会儿回来，或者上下文被压缩了：「接着指挥 ~/…/2026-10-05-限流-指挥台账.md」。

主控每一轮开头先说进度（第 n/N 步已完成；下一步：…），结尾按优先级列出需要你做的事。

### 搭配 `/goal`

Claude Code 的 [`/goal`](https://code.claude.com/docs/en/goal.md) 会让会话一直干到某个条件成立。主控会按台账给你一行：

```
/goal Every card in ~/…/限流-指挥台账.md is done or deferred with a reason and wrap-up is finished, or a question for me is pending in your last message
```

两者互补：每个 worker 一有事件，watch 就把主控叫醒；`/goal` 兜住「一轮结束了却没有 watch 在挂着」的情况，后台任务跑满 30 分钟还会让主控检查一遍 watch。遇到额度上限它会暂停，不会死循环重试。只给主控用：worker 挂着 `/goal` 就没法停下来问问题。

## 配置各个环节

`~/.config/herdr-conductor/config.toml`（你的）和 `<repo>/.herdr-conductor.toml`（项目的）覆盖[默认值](skills/herdr-conductor/config.default.toml)：

```toml
[roles.coding]
kind = "claude"
model = "opus"
effort = "high"

[roles.review]                 # 每个分支都让另一家的模型读一遍
kind = "codex"                 # model 留空：用你 Codex 的默认模型
effort = "high"

[pipeline]
review = "always"              # never | checkin | always
review_role = "review"
acceptance = "conductor"       # 或者填一个角色名，派验收 worker
max_coding_workers = 3

[merge]
strategy = "squash"
```

项目文件可以选 agent、模型和 effort，但不能加命令行 `args`：那可能关掉 worker 的沙箱。详见 [docs/configuration.md](docs/configuration.md)；`scripts/config.py show --dir <repo>` 会列出合并后的每个值和它的来源。

## 支持的 agent

| Worker | 状态 | 说明 |
|---|---|---|
| Claude Code | 支持 | 全部事件；崩了用 `--resume` 接回 |
| Codex CLI | 支持（较新） | 事件来自它的 rollout transcript；任务书送达有校验；见 [docs/agents.md](docs/agents.md) |
| 其他 Herdr agent | 未测试 | 只看屏幕：`DONE`、`BLOCKED`、`STALLED`、`IDLE`、`GONE` |

只有 Claude Code 能当主控：只有它的后台 shell 在退出时会通知。

## 安全模型

- worker 用的是**你的**权限模式。你的 shell alias 加了 `--dangerously-skip-permissions`，worker 也带着它；任务书里的「不许」只是约定，不是沙箱。真正保护分支的是：只有主控合并，而且合并前读过 diff。
- 推送、部署、账号或权限变更、破坏性操作，要么有你的长期授权，要么当场得到你的同意，并写进台账的授权一栏。
- `spawn.sh --trust` 只在 worktree 的 `.claude/` 和 `.mcp.json` 都已提交、没有改动时（也就是你自己分支的配置），才替你回答 Claude 的目录信任提示。
- 项目配置不能加命令行参数。

## 测试

`tests/run.sh <场景> --role <角色>` 会在单独的 Herdr tab 里、对一个一次性仓库启动真实的 worker，再检查它做了什么。场景和最近一次的结果矩阵见 [tests/README.md](tests/README.md)。

## 许可

MIT。Herdr 是其作者的独立项目，采用 Apache-2.0，本仓库不包含它。
