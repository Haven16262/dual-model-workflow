# Dual-Model Workflow

A lightweight protocol for pairing two AI coding models — one as **Overseer**, one as **Worker** — coordinated through three plain Markdown files. Solves single-model context exhaustion and role confusion.

**[English](#english) · [中文](#中文)**

---

## English

### The problem

When you use one AI model for a long coding session, two things go wrong:

1. **Context exhaustion** — as the conversation grows, the model loses early context, repeats mistakes, and drifts off course.
2. **Role confusion** — you want it to make architecture decisions, it edits code details; you want it to execute, it keeps asking you for direction.

This workflow splits the work across **two models with separate roles**, and manages the shared state in three files so each model only does what it's good at.

### Two roles

- **Overseer (`cc`, e.g. Claude)** — direction, decisions, review. Does not read large numbers of files, does not iterate on details. Steps in only at key moments: set architecture at kickoff, decide when the Worker hits a fork, review at phase boundaries.
- **Worker (`cc-ds`, e.g. DeepSeek)** — execution, iteration, detail implementation. Reads files, looks things up, writes code, fixes bugs. The role that actually does the work.

The two roles run in separate terminal sessions: `cc` starts the Overseer, `cc-ds` starts the Worker.

### Three files

- **`WORKFLOW.md`** — the rules: each role's responsibilities, switch trigger conditions, and the `context.md` write formats. Both models read this on startup so behavior stays consistent.
- **`CLAUDE.md`** — project-level startup instructions: every session must (1) read `WORKFLOW.md`, (2) read `context.md` (top status block first, then latest history), (3) restate "I am [role], current task is: [summary]" and begin.
- **`context.md`** — the core. A top `## Current State` block (overwritten on each write — the latest task list) plus an append-only history log (timestamped records of every decision and execution step).

### Repository layout

```
templates/   # markdown templates — platform-neutral, shared by both platforms
scripts/     # security-scan.sh — bash, runs on both platforms (Git Bash on Windows)
linux/       # bash helpers (cc / cc-ds / cc-init) — source into ~/.bashrc
windows/     # PowerShell helpers (same commands) — dot-source into $PROFILE
```

Only the shell helpers differ per platform; everything else (templates, security scan, license) is shared at the repo root. To sync a workflow change across machines: `git pull` on each machine — the sourced helper file updates in place.

One real behavioral difference between the two ports: **model switching**. The Linux version injects the DeepSeek endpoint via per-command environment variables at launch; the Windows version passes `claude --settings ~\.claude\settings.deepseek.json`. Both are scoped to a single session, so two terminals never interfere. Do not switch models by overwriting `~\.claude\settings.json` — that file is shared by every running Claude Code process, and rewriting it hot-reloads into sessions already running in other terminals. See the header comments in each helper file.

### Quick start — Linux / macOS (bash)

```bash
# 1. Clone
git clone https://github.com/Haven16262/dual-model-workflow.git
cd dual-model-workflow

# 2. Make templates discoverable (default location)
mkdir -p ~/.dual-model/templates
cp -r templates/. ~/.dual-model/templates/
#   (the trailing dot copies hidden entries like .claude/ too)
#   (or: export DUAL_MODEL_TEMPLATES=/abs/path/to/dual-model-workflow/templates)

# 2b. Install the security precheck script (used by the Overseer before every review)
mkdir -p ~/.claude/scripts
cp scripts/security-scan.sh ~/.claude/scripts/

# 3. Export your DeepSeek key in your shell profile (NEVER commit this)
echo 'export DEEPSEEK_API_KEY="sk-your-deepseek-key"' >> ~/.bashrc

# 4. Source the helpers
echo 'source '"$PWD"'/linux/dual-model.sh' >> ~/.bashrc
source ~/.bashrc

# 5. In any project directory, initialize the workflow
cd /path/to/your/project
cc-init        # copies WORKFLOW.md + CLAUDE.md + context.md + .claude/{commands,agents}/
```

> **Naming note:** `cc` shadows the system C compiler (`/usr/bin/cc`) in interactive shells. If you do C development, rename the functions in `linux/dual-model.sh` (e.g. `dm`, `dm-ds`, `dm-init`).

### Quick start — Windows (PowerShell)

```powershell
# 1. Clone
git clone https://github.com/Haven16262/dual-model-workflow.git
cd dual-model-workflow

# 2. Make templates discoverable (default location)
New-Item -ItemType Directory -Force "$env:USERPROFILE\.dual-model\templates" | Out-Null
Copy-Item -Recurse -Force templates\* "$env:USERPROFILE\.dual-model\templates\"
Copy-Item -Recurse -Force templates\.claude "$env:USERPROFILE\.dual-model\templates\"
#   (the wildcard skips hidden dirs, so .claude/ needs its own copy)
#   (or: $env:DUAL_MODEL_TEMPLATES = "C:\abs\path\to\dual-model-workflow\templates")

# 2b. Install the security precheck script (runs under Git Bash, which Claude Code ships with)
New-Item -ItemType Directory -Force "$env:USERPROFILE\.claude\scripts" | Out-Null
Copy-Item scripts\security-scan.sh "$env:USERPROFILE\.claude\scripts\"

# 3. Prepare the settings file for model switching (NEVER commit the key)
#    ~\.claude\settings.deepseek.json  — DeepSeek endpoint env + API key (Worker)
#    (the Overseer just uses your normal ~\.claude\settings.json — nothing to prepare)

# 4. Dot-source the helpers in your PowerShell profile
Add-Content $PROFILE ". `"$PWD\windows\dual-model.ps1`""
. $PROFILE

# 5. In any project directory, initialize the workflow
cd C:\path\to\your\project
cc-init        # copies WORKFLOW.md + CLAUDE.md + context.md + .claude/{commands,agents}/
```

Then use two terminals: `cc` for the Overseer, `cc-ds` for the Worker. Each silently injects the role into the system prompt (via `--append-system-prompt`, not sent as a chat message — your first message stays free for whatever you want to say) and reads `WORKFLOW.md` / `context.md` to restore state.

### Switching roles

The Worker finishes a phase or hits a decision it can't make, writes to `context.md`, and says *"written to context.md, please switch to the Overseer."* You go to the Overseer terminal and type:

> *The Worker changed something, check the context file.*

The Overseer reads it, gives a decision, writes to `context.md`, and says *"decision written, switch back to the Worker."* You go to the Worker terminal and type:

> *The Overseer changed something, check the context file.*

These two phrases are the switch signals — the model reads `context.md` on receiving them, so you never have to re-explain the background.

**Slash command alternative:** the same two switch signals are also wired up as slash commands (defined in `templates/.claude/commands/`):

- In the Overseer terminal: `/as-overseer` ≡ *"The Worker changed something, check the context file"* (i.e. "I'm now stepping in as Overseer")
- In the Worker terminal: `/as-worker` ≡ *"The Overseer changed something, check the context file"* (i.e. "I'm now stepping in as Worker")

(The `as-` naming is mnemonic: you state the role you're about to take. It's also faster to type than `from-` since `a` and `s` are adjacent on QWERTY.)

Same semantics, less typing. Hand-typed phrases still work.

### Trigger conditions (Worker → Overseer)

The Worker must stop and switch to the Overseer when:

1. There's an architecture fork with multiple options it can't choose between.
2. It hits a security- or performance-relevant design decision.
3. It finished a complete module and needs direction confirmed before continuing.
4. Two consecutive attempts still don't solve a problem.

Condition 4 matters — rather than let the Worker burn tokens trial-and-erroring, switch to the Overseer for a fresh angle.

### The review mechanism — and why

Early versions had a hidden flaw: **the Overseer was nominally supposed to "review the Worker's output at phase boundaries," but it wasn't actually reviewing anything.**

The cause was the write format. The Worker only wrote a *completion summary* and *task progress* — all **results** (what got done), no **decisions** (how, what was touched). The Overseer, holding a results summary, had no way to tell whether direction had drifted or a security pitfall was hit. Review stayed at the "looks done" surface.

The fix is not to make the Overseer read all the code (that violates its "don't read large numbers of files" principle), but to make the Worker surface key decisions on delivery. The Worker write format now carries a mandatory four-item checklist:

```
**Key decisions:** (answer every item explicitly; write "none" if none — never leave blank)
- Architecture / interface changes: ...
- Security-relevant: touches auth / secrets / user input / SQL / file paths / outbound requests?
- Deviations from plan: ...
- Unresolved doubts: things pushed past without confidence
```

This deliberately separates **fact reporting** from **risk judgment**: the Worker only answers factually ("did you change an interface", "did you touch these security-sensitive surfaces") — answerable even without understanding the risk; the Overseer judges the risk. "Unresolved doubts" is the single highest-value line — it catches the blind spot where **the Worker isn't blocked, so it never triggers a switch, but it's actually unsure**. That case used to fall straight through the net.

A paired hard rule for the Overseer: **whenever the security item is non-empty, it must invoke the `critic` subagent** (defined in [`templates/.claude/agents/critic.md`](templates/.claude/agents/critic.md), runs on Haiku) to read the relevant files and return a structured audit, rather than relying on the summary. This operationalizes the "must read code" rule without making the Overseer itself read large numbers of files — the critic does the reading and reports back; the Overseer judges from the report.

That still leaves a gap: the escape hatch is gated on the Worker's self-report, and models reflexively fill "none" (see the caveat below). The fix is an objective trigger that doesn't depend on self-reporting: before every review, the Overseer runs [`scripts/security-scan.sh`](scripts/security-scan.sh) — a pure local `grep` over the diff's added lines (zero token cost, no model call) that flags security-sensitive keywords (auth/secrets, SQL, command execution, path traversal, outbound requests). **A hit or a non-empty security item — either one — forces the `critic` invocation.** A hit doesn't mean there's a real problem, only that review gets escalated to mandatory; the script is a trigger, not a verdict.

### Why this patch doesn't auto-work (the honest caveat)

Be honest about one thing: the whole mechanism rests on the **Worker self-reporting honestly**, and the Worker is a smaller/cheaper model. Models tend to reflexively fill all four items with "none" to close out faster — especially "unresolved doubts" (admitting uncertainty is exactly what models least want to do). Once it writes "none" on the security item where it shouldn't, the "security non-empty → must read code" escape hatch is bypassed by the empty fill, and the mechanism spins idle.

So the countermeasure is not another format change — it's Overseer behavior: **early in working with a given Worker model, even when it writes "none" on the security item, spot-check the actual diff once or twice** to learn whether this Worker self-reports honestly or reflexively fills "none." Calibrate how much you trust the checklist accordingly, instead of trusting it by default. Mechanism design can only go so far; the rest is calibration from real runs.

### context.md write formats

See [`templates/WORKFLOW.md`](templates/WORKFLOW.md) for the authoritative, copy-paste formats (Overseer write, Worker write, Worker→Overseer handoff). Once the format is consistent, either side opening a new session can reconstruct the full decision chain from the history log — no more "no idea why we did it this way last time."

### Related work

Splitting AI coding work across a stronger "planner / architect" model and a weaker / cheaper "executor" model is a well-established pattern. This repo is one specific flavor of it, not a novel design. Prior art worth knowing about:

**Established frameworks:**
- [aider](https://github.com/Aider-AI/aider) — `--architect` mode pairs a planner model with an editor model in a single CLI. The most direct conceptual parent of this repo's idea.
- [MetaGPT](https://github.com/geekan/MetaGPT), [AutoGen](https://github.com/microsoft/autogen), [CrewAI](https://github.com/crewAIInc/crewAI), [LangGraph](https://github.com/langchain-ai/langgraph) — multi-agent frameworks with role-based orchestration; planner / executor is one of the canonical role splits they support.
- [cline](https://github.com/cline/cline), [Roo Code](https://github.com/RooVetGit/Roo-Cline) — IDE-embedded agents with plan / act mode separation.

**Directly overlapping smaller repos (all created shortly before this one):**
- [chewwwwwwwwww/claude-codex-hybrid-kit](https://github.com/chewwwwwwwwww/claude-codex-hybrid-kit) — structurally the closest: two Claude Code sessions sharing a Markdown file (`issue-N.md`) as the bus, with explicit slash commands (`/scope → /architect → /build → /review`). Uses Codex instead of DeepSeek and formalizes the flow as a state machine.
- [SelimCakil/claude-deepseek-architect](https://github.com/SelimCakil/claude-deepseek-architect) — same model pairing (Claude architect + DeepSeek developer) but uses MCP-based programmatic dispatch (houtini-lm) instead of human-mediated switching.
- [evan-e2438927/sdlc-workflow](https://github.com/evan-e2438927/sdlc-workflow) — a heavier SDLC-flavored variant: Claude + Codex with formal review gates, Telegram notifications, full PR automation.

**Where this repo differs (small, but real):**
- **Human-mediated switching with explicit trigger phrases**, rather than programmatic dispatch or a hidden state machine. Slower, but transparent and dependency-free — works with just Claude Code itself.
- **The four-item "Key Decisions" checklist** that the Worker must fill on every delivery, separating fact-reporting from risk-judgment.
- **An honest caveat about why the checklist doesn't auto-work** — the Worker model may reflexively answer "none" and the Overseer must spot-check diffs to calibrate trust. None of the comparable repos surface this limitation in their docs.

If you want a more automated or heavier-weight solution, prefer aider's architect mode or one of the multi-agent frameworks above. This repo is for the case where you want the dual-model split with no extra dependencies beyond Claude Code itself.

### License

MIT — see [LICENSE](LICENSE).

---

## 中文

### 问题

用单个 AI 模型做长时间开发,有两个常见问题:

1. **上下文耗尽** —— 对话越长,模型越会丢失早期上下文,反复犯同样的错,或者做着做着把方向带偏。
2. **角色混乱** —— 你想让它做架构决策,它去改代码细节;你想让它执行,它却反复问你方向。

这套工作流的思路是:**把两个模型的角色分开**,用三个文件管理协作状态,让每个模型只做自己擅长的事。

### 两个角色

- **全局者(`cc`,如 Claude)** —— 负责方向、决策、审查。不读大量文件,不做迭代修改,只在关键节点介入:项目启动定架构,工作者遇到分歧给决策,阶段完成做 review。
- **工作者(`cc-ds`,如 DeepSeek)** —— 负责执行、迭代、细节实现。读文件、查资料、写代码、改 bug,是实际干活的角色。

两个角色跑在不同的终端 session 里,`cc` 启动全局者,`cc-ds` 启动工作者。

### 三个文件

- **`WORKFLOW.md`** —— 游戏规则:两个角色各自的职责、触发切换的条件、`context.md` 的写入格式。每次 session 启动两个模型都先读它,确保行为一致。
- **`CLAUDE.md`** —— 项目级启动指令:每次 session 必须 (1) 读 `WORKFLOW.md`,(2) 读 `context.md`(先看顶部当前状态,再看最新历史),(3) 复述「我是[角色],当前任务是:[摘要]」再开始。
- **`context.md`** —— 整个工作流的核心。顶部 `## 当前状态`(每次写入覆盖,放最新任务清单)+ 仅追加的历史记录(每次写入留一条带时间戳的记录)。

### 仓库布局

```
templates/   # markdown 模板 —— 平台无关,两端共用
scripts/     # security-scan.sh —— bash 脚本,两端都能跑(Windows 走 Git Bash)
linux/       # bash helper(cc / cc-ds / cc-init)—— source 进 ~/.bashrc
windows/     # PowerShell helper(同名命令)—— dot-source 进 $PROFILE
```

只有 shell helper 按平台分开,其余(模板、安全扫描、许可证)都放仓库根共享。跨机器同步工作流更新:每台机器 `git pull` 即可,被 source 的 helper 文件原地更新。

两个移植版有一处真实的行为差异:**模型切换**。Linux 版在启动时用命令前缀环境变量注入 DeepSeek 端点;Windows 版用 `claude --settings ~\.claude\settings.deepseek.json` 传入。两种做法都只作用于单个会话,两个终端互不干扰。不要用"覆盖 `~\.claude\settings.json`"的方式切模型——那个文件被所有正在运行的 Claude Code 进程共享,改它会热重载到其它终端里已经在跑的会话上。详见各 helper 文件的头部注释。

### 快速开始 —— Linux / macOS(bash)

```bash
# 1. 克隆
git clone https://github.com/Haven16262/dual-model-workflow.git
cd dual-model-workflow

# 2. 把模板放到默认位置
mkdir -p ~/.dual-model/templates
cp -r templates/. ~/.dual-model/templates/
#   (尾部的 . 同时拷贝 .claude/ 等隐藏目录)
#   (或:export DUAL_MODEL_TEMPLATES=/绝对路径/dual-model-workflow/templates)

# 2b. 安装安全预检脚本(全局者每次审查前运行)
mkdir -p ~/.claude/scripts
cp scripts/security-scan.sh ~/.claude/scripts/

# 3. 在 shell 配置里导出你的 DeepSeek key(绝不要提交进仓库)
echo 'export DEEPSEEK_API_KEY="sk-your-deepseek-key"' >> ~/.bashrc

# 4. 引入 helper
echo 'source '"$PWD"'/linux/dual-model.sh' >> ~/.bashrc
source ~/.bashrc

# 5. 在任意项目目录初始化工作流
cd /你的/项目
cc-init        # 复制 WORKFLOW.md + CLAUDE.md + context.md + .claude/{commands,agents}/
```

> **命名提醒:** `cc` 会在交互 shell 里覆盖系统 C 编译器(`/usr/bin/cc`)。如果你做 C 开发,改掉 `linux/dual-model.sh` 里的函数名(如 `dm`、`dm-ds`、`dm-init`)。

### 快速开始 —— Windows(PowerShell)

```powershell
# 1. 克隆
git clone https://github.com/Haven16262/dual-model-workflow.git
cd dual-model-workflow

# 2. 把模板放到默认位置
New-Item -ItemType Directory -Force "$env:USERPROFILE\.dual-model\templates" | Out-Null
Copy-Item -Recurse -Force templates\* "$env:USERPROFILE\.dual-model\templates\"
Copy-Item -Recurse -Force templates\.claude "$env:USERPROFILE\.dual-model\templates\"
#   (通配符不带隐藏目录,.claude/ 要单独复制一次)
#   (或:$env:DUAL_MODEL_TEMPLATES = "C:\绝对路径\dual-model-workflow\templates")

# 2b. 安装安全预检脚本(在 Git Bash 下运行,Claude Code 自带)
New-Item -ItemType Directory -Force "$env:USERPROFILE\.claude\scripts" | Out-Null
Copy-Item scripts\security-scan.sh "$env:USERPROFILE\.claude\scripts\"

# 3. 准备模型切换用的 settings(key 绝不要提交进仓库)
#    ~\.claude\settings.deepseek.json  — DeepSeek 端点 env + API key(工作者)
#    (全局者直接用你正常的 ~\.claude\settings.json,不用另外准备)

# 4. 在 PowerShell profile 里 dot-source helper
Add-Content $PROFILE ". `"$PWD\windows\dual-model.ps1`""
. $PROFILE

# 5. 在任意项目目录初始化工作流
cd C:\你的\项目
cc-init        # 复制 WORKFLOW.md + CLAUDE.md + context.md + .claude/{commands,agents}/
```

然后开两个终端:`cc` 跑全局者,`cc-ds` 跑工作者。各自会把角色静默注入系统提示(通过 `--append-system-prompt`,不作为聊天消息发送——第一条消息仍留给你说别的)并读 `WORKFLOW.md` / `context.md` 恢复状态。

选完角色后,脚本还会问一句**本轮话题**(可选,回车跳过)。它和项目目录、角色一起构成会话名(通过 `--name`),格式三段:

```
<项目目录名>-<角色>-<本轮话题>       # 例:bili-overseer-登录态重构
<项目目录名>-<角色>-<MMDD-HHMM>     # 回车跳过话题时的兜底,例:bili-worker-0820-1145
```

三段各有各的用处,少一段都会出问题:

- **项目目录名**——并行开两个项目时,固定叫 `worker` 会让交接消息投递到**另一个项目**的工作者那里,比没有自动化更糟。
- **角色**——同一项目里区分两个终端,交接消息靠它定向。
- **话题**——同一项目每次启动都重名的话,`/resume` 列表里会堆出一排一模一样的条目,你分不出哪个是哪次。`--name` 还会**覆盖** Claude Code 本来会自动生成的摘要标题,所以固定名字不只是没帮上忙,是把原本有用的标题换成了无用的。

代价是发送方不再能凭 cwd 算出对方的完整名字(话题是对方自己填的),发消息前要跑一次 `ListAgents` 按前缀找——见下一节。

### 切换角色

工作者完成一个阶段或遇到无法决策的问题,写入 `context.md` 后说「已写入 context.md,请切换到全局者」。你去全局者终端输入:

> 「工作者修改了内容,查看 context 文件」

全局者读取后给决策,写入 `context.md`,再说「决策已写入,可切换回工作者继续」。你去工作者终端输入:

> 「全局者修改了内容,查看 context 文件」

这两句话是切换信号,模型收到后会主动读 `context.md`,不需要你重新解释背景。

**Slash 命令简化:** 两句切换话语都有等价的 slash 命令(定义在 `templates/.claude/commands/`):

- 全局者终端:`/as-overseer` ≡ 「工作者修改了内容,查看 context 文件」(意:我现在接手全局者角色)
- 工作者终端:`/as-worker` ≡ 「全局者修改了内容,查看 context 文件」(意:我现在接手工作者角色)

(`as-` 而不是 `from-` 有两个理由:语义上"我现在是什么角色"比"来自谁"更直觉;键盘上 a/s 相邻,比 `from-` 起手 f→r 跨距小,输入更顺。)

语义相同,少打字。手打话语仍然有效。

### 让会话自己通知对方

上面那两步「你走到另一个终端敲字」可以省掉。Claude Code 支持跨会话消息(`SendMessage` + `ListAgents`),两个终端同时开着时,写完 `context.md` 的一方直接通知对方,对方按 `/as-worker` / `/as-overseer` 的完整流程接手。

版本门槛分两档:**macOS / Linux / WSL 2 需 ≥ 2.1.224,原生 Windows 需 ≥ 2.1.234**。用 `/list-agents`(别名 `/peers`)自查:命令本身不认识就是没有这个功能。

会话名的前两段(项目目录 + 角色)发送方算得出,第三段话题算不出。所以发消息前**跑一次 `ListAgents`**,找名字以 `bili-worker-` 开头的那一行,按行里印的完整名字发送;**恰好一条**才发,零条或多条一律回退人工。这一次查询是流程的一部分,不是故障排查。

名字唯一时直接按名字投递,不再需要先带 `[ref]` 确认(2.1.232 起)。你自己也可以在 prompt 里打 `@` 加名字前几个字母,从候选里挑一个会话点名——省掉让模型先查一遍。

一条铁律:**消息只负责叫醒和指路,决策内容一律仍然写 `context.md`。**

> 这条不是洁癖。本工作流的核心承诺是「任何一方新开 session 都能只靠文件还原完整决策链」;消息是易失的,不进文件就等于没发生过。一旦决策开始走消息,承诺立刻作废,而且失效得悄无声息——当下能跑,回头追溯时才发现断链。

发送失败(对方没开终端、名字对不上、版本或平台不支持)时,**回退到人工中转,不重试**。所以这是可选加速,不是新的必经路径:自动通道断了,工作流退化成原来的样子,照常运转。

**可选:让平台替你盯着。** 全局者交出任务时可以带上 `notify_when_idle`(≥ 2.1.236,仅同机器),请平台在工作者下次空闲时回一条通知。好处是不依赖工作者记得发消息;代价是它只说「空闲了」,不说「交接好了」——收到后仍要读 `context.md` 确认有没有新交接块。

**平台状态:** 跨会话消息最初只有 macOS 和 Linux,Windows 从 2.1.234 起补齐,现在三端都可用。但 **`windows/dual-model.ps1` 还没跟进**——它不设置会话名,所以 Windows 端目前仍走人工中转(规则会自动回退,行为等同于本节不存在)。模板不为平台分叉,等 PowerShell 侧补上会话命名后本节对 Windows 同样生效。

同机器上两个终端直接走本地 socket(Windows 上是命名管道),不经过 Anthropic 服务器;**跨机器**(比如 VPS 和本地电脑)才需要两端都连 Remote Control,消息经服务器中转。另外 WSL 2 里的会话和同一台电脑上的原生 Windows 会话**互相看不见**——注册在不同的 home 目录,socket 类型也不同。

**别指望它做无人值守自动循环。** 发给「已跳过权限确认」会话的跨会话消息会被扣住等人工批准(平台设计如此)。这套机制省的是打字和上下文切换,不省盯着——这跟本工作流「人是检查点」的前提是一致的。

### 触发切换的条件(工作者 → 全局者)

工作者遇到以下情况必须停下切换到全局者:

1. 出现架构方向分歧,有多个方案无法判断选哪个。
2. 遇到安全、性能相关的设计决策。
3. 完成一个完整模块,需要确认方向再继续。
4. 连续两次尝试仍无法解决某个问题。

条件 4 很重要 —— 与其让工作者反复试错消耗 token,不如切到全局者换个思路。

### 审查机制 —— 以及为什么

早期版本有个藏得很深的问题:**全局者名义上要「阶段性审查工作者输出」,但实际上它根本没在审查。**

问题出在写入格式。工作者完成后只写「完成情况」和「任务进度」—— 全是结果(做完了什么),没有决策(怎么做的、动了什么)。全局者拿着结果摘要,无从判断方向有没有偏、有没有踩安全坑,审查只能停在「看起来做完了」的表面。

修法不是让全局者去读全部代码(那违背它「不读大量文件」的原则),而是让工作者在交付时主动暴露关键决策。工作者写入格式现在带四项强制清单:

```
**关键决策点:**(每项必须显式回答,无则写「无」,不留空)
- 架构/接口变动:...
- 安全相关:是否涉及 认证/密钥/用户输入/SQL/文件路径/外部请求
- 偏离原计划:...
- 未解决的疑虑:继续推进但没把握的点
```

这里有意把**事实上报**和**风险判断**分开:工作者只需如实回答「改没改接口」「碰没碰这些安全敏感面」—— 即使不懂风险也答得出;风险判断交给全局者。其中「未解决的疑虑」是单条价值最高的一项,专门抓那种**工作者没卡住、所以从不触发切换、但其实心里没底**的盲区 —— 这种情况以前完全漏在网外。

配套给全局者加一条硬规则:**只要安全项非空,就必须 invoke `critic` 子代理**(定义在 [`templates/.claude/agents/critic.md`](templates/.claude/agents/critic.md),用 Haiku 跑)去读相关文件并返回结构化审查报告,不能只看摘要。这把"必须读代码"规则操作化了 —— 全局者自己仍不读大量文件,由 critic 子代理代读并出报告,全局者凭报告判断。

但这仍留了一个缺口:逃生口的开关挂在工作者自报上,而模型会反射性填「无」(见下面的告诫)。对策是加一层不依赖自报的客观触发器:全局者每次审查前先跑 [`scripts/security-scan.sh`](scripts/security-scan.sh) —— 纯本地 `grep` 扫 diff 新增行(零 token、不调模型),命中认证/密钥、SQL、命令执行、路径穿越、外部请求等安全敏感关键词就报警。**脚本命中或安全项非空,二者任一,都强制走 `critic` 子代理审查。**命中不等于真有问题,只是把审查从"可选"升级为"必须",脚本给的是触发信号,不是结论。

### 这个补丁不会自动生效(诚实的告诫)

得诚实说一点:整套机制押在工作者**自报诚实**上,而工作者是更小/更便宜的模型。模型有个倾向 —— 为尽快收尾把四项反射性全填「无」,尤其「未解决的疑虑」(承认不确定恰恰是模型最不愿做的)。一旦它在安全项该填却填了「无」,前面那个「安全项非空→必读代码」的逃生口就被空填绕过,整套机制空转。

所以对策不在再改格式,而在全局者的行为:**与某个工作者模型协作的早期,即使它安全项写「无」,也要拿实际 diff 抽查一两次**,先摸清这个工作者到底是诚实自报还是反射填「无」,据此校准对清单的信任度,而不是默认全信。机制设计能做的到此为止,剩下的得靠实跑校准。

### context.md 写入格式

权威的可复制格式(全局者写入、工作者写入、工作者→全局者交接)见 [`templates/WORKFLOW.md`](templates/WORKFLOW.md)。格式统一后,任何一方开启新 session 都能通过历史记录还原完整决策链,不会出现「不知道上次为什么这么做」。

### 相关工作

把 AI 编码工作拆给一个强"规划者 / 架构师"模型 + 一个弱 / 更便宜的"执行者"模型,这个模式有大量先例。本仓库只是其中一种特定实现,不是新颖设计。值得知道的 prior art:

**成熟框架:**
- [aider](https://github.com/Aider-AI/aider) —— `--architect` 模式在单一 CLI 内把规划者模型和编辑者模型配对。是本仓库思路最直接的概念父本。
- [MetaGPT](https://github.com/geekan/MetaGPT)、[AutoGen](https://github.com/microsoft/autogen)、[CrewAI](https://github.com/crewAIInc/crewAI)、[LangGraph](https://github.com/langchain-ai/langgraph) —— 多 agent 框架,角色化编排,规划者 / 执行者是它们支持的经典分工之一。
- [cline](https://github.com/cline/cline)、[Roo Code](https://github.com/RooVetGit/Roo-Cline) —— IDE 内嵌的 agent,带 plan / act 模式分离。

**直接重叠的小仓库(均在本仓库之前不久创建):**
- [chewwwwwwwwww/claude-codex-hybrid-kit](https://github.com/chewwwwwwwwww/claude-codex-hybrid-kit) —— 结构上最接近:两个 Claude Code session 共享一个 Markdown 文件(`issue-N.md`)作总线,带显式 slash commands(`/scope → /architect → /build → /review`)。用 Codex 而非 DeepSeek,并把流程形式化成状态机。
- [SelimCakil/claude-deepseek-architect](https://github.com/SelimCakil/claude-deepseek-architect) —— 模型对完全一致(Claude 架构师 + DeepSeek 开发者),但用 MCP 程序化派发(houtini-lm),不是人介入切换。
- [evan-e2438927/sdlc-workflow](https://github.com/evan-e2438927/sdlc-workflow) —— 偏重 SDLC 流程的变体:Claude + Codex,带形式化审查门禁、Telegram 通知、PR 自动化。

**本仓库的差异点(小,但真实):**
- **人介入切换 + 显式触发话语**,而非程序化派发或隐藏状态机。代价是慢,好处是透明、零额外依赖——只要有 Claude Code 就能跑。
- **四项「关键决策点」清单**,工作者每次交付强制填,事实上报与风险判断分离。
- **关于清单为何不自动生效的诚实告诫**——工作者模型可能反射性填「无」,全局者需要抽查 diff 校准信任度。上述对应仓库的文档里都没有这条。

如果你想要更自动化 / 更重型的方案,优先选 aider 的 architect 模式或上述多 agent 框架。本仓库面向的场景是:你想要双模型分工,但不想引入 Claude Code 之外的任何额外依赖。

### 许可证

MIT —— 见 [LICENSE](LICENSE)。
