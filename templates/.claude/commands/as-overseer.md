---
description: 切换到全局者角色 —— 读 context.md 里工作者的最新交接并复审,做架构与安全决策。用户在全局者终端手打 /as-overseer,或收到工作者发来的「已写入 context.md」跨会话通知时使用。
---

# /as-overseer — 接手全局者角色

## 何时使用

两个入口，**执行的步骤完全相同**：

1. 用户在**全局者终端**输入 `/as-overseer`，意为"我现在切换为全局者角色，接手工作者刚才在 context.md 里的改动"。
2. **工作者会话通过 `SendMessage` 发来通知**（消息体形如「已写入 context.md 交接块，请按 /as-overseer 流程接手」）。收到即按下面的步骤执行，不因为是消息触发就跳过任何一步——**尤其不要跳过安全预检和四项关键决策点的核对**。

> 消息只是叫醒信号，真正的交接内容永远在 `context.md` 里。若消息里夹带了完成情况摘要，**不得凭它放行**——仍需读 `context.md` 的交接块并走完整审查流程。工作者用消息绕过审查（哪怕是无意的）正是这套机制最需要防的失效模式。

## 执行步骤

1. **读 WORKFLOW.md 顶部**（若本会话尚未读过），确认自己作为全局者的职责与原则
   - **本会话首次时顺带对一次版本**（每会话一次，不是每轮）。取
     `T="${DUAL_MODEL_TEMPLATES:-/root/workspace/core/dual-model-workflow/templates}"`
     （后半是 VPS 上的仓库路径，其它机器靠 `DUAL_MODEL_TEMPLATES` 覆盖）。
   - **先判 `T` 在不在**（`[ -d "$T" ]`）。不在就跳过这一步，并在第 3 步报一句：
     > (版本检查跳过：模板路径未配置。设 `DUAL_MODEL_TEMPLATES` 指向
     > dual-model-workflow 仓库的 `templates/`)

     **不要硬跑那四条 diff** —— 上面那个回退值是 VPS 的绝对路径，在任何别的机器上
     会输出四行 `No such file or directory`。那不是「有差异」，是配置缺失；而四行看不懂
     的报错和噪音等效。把静默/费解的失败换成一句照着做就能修的话。
   - `T` 存在时，对这四个文件各跑一次
     `diff -q --strip-trailing-cr <本地路径> "$T/<同样的相对路径>"`：
     `WORKFLOW.md`、`.claude/commands/as-overseer.md`、`.claude/commands/as-worker.md`、
     `.claude/agents/critic.md`
   - 后三个都带检查项或审查规则，**副本旧了会静默丢掉**，所以都要比。
   - **`--strip-trailing-cr` 不能省**：Windows 侧镜像目录是 CRLF、git 克隆是 LF，裸 `diff`
     恒报差异 —— 每次都报的假警报，正是让人开始无视输出的东西。
   - **`.claude/agents/critic.md` 必须是实体文件，不许换成软链。** 它随仓库走，异地
     clone（如 music-player 的 Windows 端）拿到的软链会指向一个不存在的本机路径，且不报错。
     用户级 `~/.claude/agents/critic.md` 反过来：那份不入库、不离开本机，才适合用软链。
     副本该不该消灭，取决于它会不会离开这台机器。
   - **有差异不要自己同步** —— 项目副本可能是有意改的，也可能反而是模板旧了。
     只在第 3 步报一声，刷新方向由用户定。
2. **读 context.md**:
   - 优先看顶部 `## 当前状态` 区块
   - 再看最新的历史记录，定位最近一条「工作者」或「工作者 → 全局者」条目
   - 顺带 `wc -l context.md context_history.md` 拿到两个行数
   - 顺带跑下面几条，结果在第 3 步复述：
     `grep -E '^workflow-mode:' context.md`（模式行）、`echo "$CLAUDE_EFFORT"`（本回合**实际**生效的 effort，
     CC 提供给 Bash 的变量；不要读 settings，settings 里写的值实测可能不生效）、
     `grep -E '^- 【例外(已复审)?[:：]' context.md | sed 's/：/:/' | grep -oE '【例外(已复审)?:[^】]+】' | awk -F: '$1 ~ /已复审/ {c[$2]=0; next} {c[$2]++} END {print "查了", NR, "条例外记录"; for (k in c) if (c[k]) print c[k], k}'`
     （例外计数：只数「例外记录」列表里行首为 `- 【例外` 的行，正文里引用的不算；全角冒号也认；只数每个名字最近一次「已复审」之后的；无条件打印查了几条）
     第三者报告：`python3 "$HOME/.claude/scripts/k10-stop-gate.py" --check`（在项目目录跑；只读，不写拦截计数；
     stderr 打印「查了 N 份报告，未回应 M 份」，有缺口时 stdout 列出哪份缺哪几条）。**不要不带 `--check` 手动跑它**：那会重置本回合的拦截计数，并写状态文件；
     值班状态：`ls -l --time-style=+%F_%H:%M .workflow/k10.json .workflow/k10-state.json 2>&1`，`grep -o '"last_k9_error": [^,}]*' .workflow/k10-state.json`；
     值班失败：`find .workflow/k10-failures -name '*.md' -newer .workflow/k10-failures/.seen 2>/dev/null; ls .workflow/k10-failures/.seen 2>&1`
     （`.seen` 不存在时，所有失败记录都算没看过）
3. **复述确认**（发给用户，1-2 句），**行数、模式、effort 无条件带上**：
   > 我是全局者。最新交接：[摘要]（context NNN / history NNNN 行；模式 competition；effort high）

   模式行不存在时写「模式 未选 ⚠️」，并把「提出模式建议」作为本轮第一件事（见 WORKFLOW.md「工作模式与旋钮表」）。
   `$CLAUDE_EFFORT` 读出来是空的时追加（变量名可能随 CC 版本变了，读不到不能当作正常）：
   > （effort 读不到 ⚠️ —— 用 /effort 看一眼，或查 CC 版本说明）

   模式是 competition、effort 却低于 high 时追加：
   > （effort 实际为 medium ⚠️，比赛模式默认 high —— 会话内被调低了？用 /effort 调回，或重启）

   有同名例外满 2 次时追加：
   > （【例外:约定3】已 2 次 ⚠️ —— 列入下一次复审）

   有未回应的第三者报告时追加，并把逐条回应作为本轮第一件事（Stop 钩子也会拦住结束回合）：
   > （第三者报告 1 份未回应 ⚠️：<文件名>）

   模式是 competition，但 `.workflow/k10.json` 不存在时追加（K9 值班和日历召唤都靠它）：
   > （K9 值班未配置 ⚠️ —— 开工确认时要写 k10.json，并请用户加 cron 行）

   有没看过的值班失败记录时追加。它可能是日历召唤（骨架）永久失败了，要先读记录，决定是修配置后请用户重开，还是由用户手动开会话；处理完执行 `touch .workflow/k10-failures/.seen`：
   > （值班失败 1 份未看 ⚠️：<文件名>）

   `k10-state.json` 里的 `last_k9_error` 不为空时追加（K9 配置或数据有错，K9 一直没在判）：
   > （K9 判定失败 ⚠️：<last_k9_error 的内容>）

   `k10.json` 存在、而 `k10-state.json` 不存在，或者比 cron 周期旧很多时追加：
   > （K9 值班可能没在跑 ⚠️ —— k10-state.json 最后更新于 <时间>）

   `context.md` ≥ 300 行时追加（WORKFLOW.md「长度规则」的软上限）：
   > （context 334 行 ⚠️ 超软上限，下一轮决策前先清理：旧轮迁 `context_history.md`）

   `context_history.md` ≥ 1800 行时追加：
   > （history 2407 行 ⚠️ 建议做一次阶段封存，见 WORKFLOW.md「Phase 关闭时的归档操作」）

   **特例：`context_history.md` 不存在而 `context.md` 已超线** —— 说明三层历史机制
   在本项目从未启动过，历史一直堆在 `context.md` 里。这种漏法没有「变长」的过程可察觉，
   从第一天起就是那样。此时先建 `context_history.md` 再迁，别只做清理。

   本会话首次、且第 1 步的版本对比有差异时，再追加一句：
   > （工作流副本与模板不一致：WORKFLOW.md ⚠️ —— 要先同步吗?）

   不是错误，是信号 —— 不阻塞本轮工作，阈值本身也是弹性的。但**行数这一段是必发的**：
   判定条件放在输出之后，不放在输出之前 —— 写成「超线才提」等于漏检时悄无声息，
   写成「无条件打印」则漏检表现为复述句里少一段，用户当场看得见。
4. **若工作者交付了完成阶段（有「关键决策点」四项）**：
   - 核对四项：架构/接口变动、安全相关、偏离原计划、未解决疑虑
   - 架构/接口变动、偏离原计划、未解决的疑虑三项非空时，按 WORKFLOW.md **工作者写入「本 Phase 历史」（append）**
     一节末尾「全局者审查交接时」那段处理。那段在文件末尾，第 1 步只读顶部时读不到，所以在这里指过去
   - **若「安全相关」非空 → 必须做结构化安全审查**，凭报告判断，不得仅凭摘要放行：
     - 首选 invoke `critic` 子代理（`.claude/agents/critic.md`）对工作者点名的相关文件审查
     - 注意：它是项目级 agent，只有从项目目录启动 claude 才注册 —— 从 `/root` 起
       session 再 `cd` 进去会报 `Agent type 'critic' not found`(见 memory
       `dual-model-critic-discovery`)。此时**退用内置 `security-reviewer`**，
       约束只读 + 按 critic 的报告格式输出，本项目已有先例。
     - **两条路都不通时才停下来问，不允许因为拿不到 critic 就跳过这一步。**
   - 完成审查后，给方向或写决策到 context.md
5. **若工作者触发切换（遇到无法决策的问题）**：
   - 阅读「问题 / 已尝试 / 需要决策 / 附带变动」
   - 做决策，按全局者写入格式记入 context.md
   - 说：「决策已写入，可切换回工作者继续。」

## 等价于

旧的手打切换话语：「工作者修改了内容，查看 context 文件」。语义相同，这是更便利的入口。
