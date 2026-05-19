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

### Quick start

```bash
# 1. Clone
git clone https://github.com/Haven16262/dual-model-workflow.git
cd dual-model-workflow

# 2. Make templates discoverable (default location)
mkdir -p ~/.dual-model/templates
cp templates/* ~/.dual-model/templates/
#   (or: export DUAL_MODEL_TEMPLATES=/abs/path/to/dual-model-workflow/templates)

# 3. Export your DeepSeek key in your shell profile (NEVER commit this)
echo 'export DEEPSEEK_API_KEY="sk-your-deepseek-key"' >> ~/.bashrc

# 4. Source the helpers
echo 'source '"$PWD"'/shell/dual-model.sh' >> ~/.bashrc
source ~/.bashrc

# 5. In any project directory, initialize the workflow
cd /path/to/your/project
cc-init        # copies WORKFLOW.md + CLAUDE.md + context.md
```

Then use two terminals: `cc` for the Overseer, `cc-ds` for the Worker. Each prints a role prompt and reads `WORKFLOW.md` / `context.md` to restore state.

> **Naming note:** `cc` shadows the system C compiler (`/usr/bin/cc`) in interactive shells. If you do C development, rename the functions in `shell/dual-model.sh` (e.g. `dm`, `dm-ds`, `dm-init`).

### Switching roles

The Worker finishes a phase or hits a decision it can't make, writes to `context.md`, and says *"written to context.md, please switch to the Overseer."* You go to the Overseer terminal and type:

> *The Worker changed something, check the context file.*

The Overseer reads it, gives a decision, writes to `context.md`, and says *"decision written, switch back to the Worker."* You go to the Worker terminal and type:

> *The Overseer changed something, check the context file.*

These two phrases are the switch signals — the model reads `context.md` on receiving them, so you never have to re-explain the background.

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

A paired hard rule for the Overseer: **whenever the security item is non-empty, it must actually read that code, not just the summary.** This is the escape hatch for security-relevant changes — lightweight self-report by default, fall back to real review the moment a security surface is touched.

### Why this patch doesn't auto-work (the honest caveat)

Be honest about one thing: the whole mechanism rests on the **Worker self-reporting honestly**, and the Worker is a smaller/cheaper model. Models tend to reflexively fill all four items with "none" to close out faster — especially "unresolved doubts" (admitting uncertainty is exactly what models least want to do). Once it writes "none" on the security item where it shouldn't, the "security non-empty → must read code" escape hatch is bypassed by the empty fill, and the mechanism spins idle.

So the countermeasure is not another format change — it's Overseer behavior: **early in working with a given Worker model, even when it writes "none" on the security item, spot-check the actual diff once or twice** to learn whether this Worker self-reports honestly or reflexively fills "none." Calibrate how much you trust the checklist accordingly, instead of trusting it by default. Mechanism design can only go so far; the rest is calibration from real runs.

### context.md write formats

See [`templates/WORKFLOW.md`](templates/WORKFLOW.md) for the authoritative, copy-paste formats (Overseer write, Worker write, Worker→Overseer handoff). Once the format is consistent, either side opening a new session can reconstruct the full decision chain from the history log — no more "no idea why we did it this way last time."

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

### 快速开始

```bash
# 1. 克隆
git clone https://github.com/Haven16262/dual-model-workflow.git
cd dual-model-workflow

# 2. 把模板放到默认位置
mkdir -p ~/.dual-model/templates
cp templates/* ~/.dual-model/templates/
#   (或:export DUAL_MODEL_TEMPLATES=/绝对路径/dual-model-workflow/templates)

# 3. 在 shell 配置里导出你的 DeepSeek key(绝不要提交进仓库)
echo 'export DEEPSEEK_API_KEY="sk-your-deepseek-key"' >> ~/.bashrc

# 4. 引入 helper
echo 'source '"$PWD"'/shell/dual-model.sh' >> ~/.bashrc
source ~/.bashrc

# 5. 在任意项目目录初始化工作流
cd /你的/项目
cc-init        # 复制 WORKFLOW.md + CLAUDE.md + context.md
```

然后开两个终端:`cc` 跑全局者,`cc-ds` 跑工作者。各自会打印角色提示并读 `WORKFLOW.md` / `context.md` 恢复状态。

> **命名提醒:** `cc` 会在交互 shell 里覆盖系统 C 编译器(`/usr/bin/cc`)。如果你做 C 开发,改掉 `shell/dual-model.sh` 里的函数名(如 `dm`、`dm-ds`、`dm-init`)。

### 切换角色

工作者完成一个阶段或遇到无法决策的问题,写入 `context.md` 后说「已写入 context.md,请切换到全局者」。你去全局者终端输入:

> 「工作者修改了内容,查看 context 文件」

全局者读取后给决策,写入 `context.md`,再说「决策已写入,可切换回工作者继续」。你去工作者终端输入:

> 「全局者修改了内容,查看 context 文件」

这两句话是切换信号,模型收到后会主动读 `context.md`,不需要你重新解释背景。

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

配套给全局者加一条硬规则:**只要安全项非空,就必须实际去读那段代码,不能只看摘要。** 这是给安全相关改动留的逃生口 —— 默认走轻量自报,一旦触到安全面就回退到真审查。

### 这个补丁不会自动生效(诚实的告诫)

得诚实说一点:整套机制押在工作者**自报诚实**上,而工作者是更小/更便宜的模型。模型有个倾向 —— 为尽快收尾把四项反射性全填「无」,尤其「未解决的疑虑」(承认不确定恰恰是模型最不愿做的)。一旦它在安全项该填却填了「无」,前面那个「安全项非空→必读代码」的逃生口就被空填绕过,整套机制空转。

所以对策不在再改格式,而在全局者的行为:**与某个工作者模型协作的早期,即使它安全项写「无」,也要拿实际 diff 抽查一两次**,先摸清这个工作者到底是诚实自报还是反射填「无」,据此校准对清单的信任度,而不是默认全信。机制设计能做的到此为止,剩下的得靠实跑校准。

### context.md 写入格式

权威的可复制格式(全局者写入、工作者写入、工作者→全局者交接)见 [`templates/WORKFLOW.md`](templates/WORKFLOW.md)。格式统一后,任何一方开启新 session 都能通过历史记录还原完整决策链,不会出现「不知道上次为什么这么做」。

### 许可证

MIT —— 见 [LICENSE](LICENSE)。
