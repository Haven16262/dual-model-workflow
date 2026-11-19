---
description: 切换到全局者角色 —— 读 context.md 里工作者的最新交接并复审,做架构与安全决策。用户在全局者终端手打 /as-overseer,或收到工作者发来的「已写入 context.md」跨会话通知时使用。
---
<!-- dmw-template: .claude/commands/as-overseer.md r21 sha=d9f146f363ee -->

# /as-overseer — 接手全局者角色

## 何时使用

两个入口，**执行的步骤完全相同**：

1. 用户在**全局者终端**输入 `/as-overseer`，意为"我现在切换为全局者角色，接手工作者刚才在 context.md 里的改动"。
2. **工作者会话通过 `SendMessage` 发来通知**（消息体形如「已写入 context.md 交接块，请按 /as-overseer 流程接手」）。收到即按下面的步骤执行，不因为是消息触发就跳过任何一步——**尤其不要跳过安全预检和四项关键决策点的核对**。

> 消息只是叫醒信号，真正的交接内容永远在 `context.md` 里。若消息里夹带了完成情况摘要，**不得凭它放行**——仍需读 `context.md` 的交接块并走完整审查流程。工作者用消息绕过审查（哪怕是无意的）正是这套机制最需要防的失效模式。

## 执行步骤

1. **读 WORKFLOW.md 与 `.workflow/overseer.md`**（若本会话尚未读过；前者是两个角色共用的部分，后者是全局者手册，正文原样从 WORKFLOW.md 拆出，WORKFLOW.md 文首的章节索引说明哪章在哪个文件），确认自己作为全局者的职责与原则
   - **本会话首次时顺带对一次版本**（每会话一次，不是每轮）：在项目根目录跑 `python3 ~/.claude/scripts/dmw-version.py check .`
     （只读。逐个比对 WORKFLOW.md、`.workflow/overseer.md`、两个 as-*.md、critic.md 与模板的版本戳和内容；
     CRLF 不算差异；退出 0 = 都是现行版本，3 = 有落后或本地改过，逐行列出；1 或 2 = 没跑成，它会说原因 —— 不要当作没有差异）。
     脚本不存在（`No such file`，如只装了公开仓的模板）：在第 3 步报一句「版本检查跳过：dmw-version.py 不存在」，不阻塞。
   - **有差异不要自己同步** —— 项目副本可能是有意改的，也可能反而是模板旧了。
     只在第 3 步报一声，刷新方向由用户定；要升时用 `dmw-version.py upgrade <项目目录>` 出计划（默认不写文件）。
2. **读 context.md**:
   - 优先看顶部 `## 当前状态` 区块
   - 再看最新的历史记录，定位最近一条「工作者」或「工作者 → 全局者」条目
   - 顺带 `python3 "$HOME/.claude/scripts/ctx-size.py" context.md; wc -l context_history.md`，拿到 context.md 的行数、
     字符数（均已排除 `⚠️ 已证伪` 墓碑，并印出「查了 N 条墓碑」）、字符线比较（印出「超线/未超线」）和 history 行数；
     ctx-size.py 非零退出表示墓碑格式或字符线认不出，照实告诉用户，不要当作没超线
   - 顺带 `python3 "$HOME/.claude/scripts/ctx-pointers.py" context.md`：查「本 Phase 历史」里指向会被覆盖内容的指针
     （「见当前状态…」「见顶部」「见上一条」，规则见 WORKFLOW.md「撰写权限」）。它逐行全查，退出码 0/3 时印一行「查了第 a..b 行…悬空指针 N 处，其中疑似在代码块/注释里 J 处」，
     3 = 有命中，并逐条列出（标「疑似在代码块/注释里」的也算命中）；1 = 范围算不出（段落布局认不出），2 = 读取失败 —— 1 和 2 都照实告诉用户，不要当作没有命中
   - 顺带安全预检 `bash ~/.claude/scripts/security-scan.sh <base>`（在项目根目录跑，它只扫当前目录这棵子树）：
     `<base>` 取所有「放行到 `<sha>`」里最新的那个（含已归档的 `context_history.md` 和封存件 `context_history-archive-*.md`）：
     `` for s in $(cat context_history*.md context.md 2>/dev/null | grep -o '放行到 `[0-9a-f]\{7,40\}`' | grep -o '[0-9a-f]\{7,40\}'); do git merge-base --is-ancestor "$s" HEAD 2>/dev/null && git rev-list --count "$s" | sed "s/$/ $s/"; done | sort -n | tail -1 | cut -d' ' -f2 ``
     （只收 HEAD 的祖先，其中按祖先提交数取最大的，不按文本先后 —— 封存件之间的文件名顺序不是时间顺序；
     仓库里找不到、或不在当前历史上的 sha（如改写过历史后）自动略过，全被略过时同「一条放行记录都没有」）。
     一条放行记录都没有时（项目首轮），用首个提交 `git rev-list --max-parents=0 HEAD | tail -1`，复述里写「base 首个提交」——
     首个提交自身的改动不在 diff 里，这一轮另把它当作「安全相关非空」处理。**不要不带参数跑**：那只扫未提交改动，工作者已提交的代码一行都扫不到。
     退出码按脚本定义：0 = 未命中；1 = 命中，本轮必须做第 4/5 步的结构化安全审查；
     2 = 没跑成（不在 git 工作树里、还没有提交、`<base>` 不是一个 commit、参数多于 1 个）—— **2 不是未命中**
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
     会话注册表：`[ -f ~/.claude/scripts/sessions-md.py ] || echo "sessions-md.py 不存在"; [ -f sessions.md ] || echo "sessions.md 未生成"; out=$(python3 ~/.claude/scripts/sessions-md.py . --dry-run 2>&1 >/dev/null); echo "sessions-md rc=$?"; printf '%s\n' "$out" | grep -o '为空的角色会话 [0-9]* 行' || printf '%s\n' "$out" | tail -2`
     （在项目根目录跑。`--dry-run` 只读：不加锁、不写文件；表丢掉，只留 stderr 里的摘要。N =「已结束但『做了什么』为空的全局者 / 工作者会话」行数，是趋势数字，不是告警；存量项目的 N 是基线）
3. **复述确认**（发给用户，1-2 句），**行数、模式、effort、安全预检退出码、sessions.md 空备注数无条件带上**：
   > 我是全局者。最新交接：[摘要]（context NNN 行 / NNNNN 字符 / history NNNN 行；模式 competition；effort high；预检 rc=0，base a1b2c3d；sessions.md 空备注 36 行）

   base 用的是首个提交时写「预检 rc=0，base 首个提交」。退出码 1 时追加：
   > （安全预检命中 N 处 ⚠️ —— 本轮做结构化安全审查，见第 4/5 步）

   退出码 2 时追加，先修好重跑（多半是 base 写错）；修不好就按命中处理，照样做结构化安全审查：
   > （安全预检没跑成 ⚠️：<它的 stderr>）

   模式行不存在时写「模式 未选 ⚠️」，并把「提出模式建议」作为本轮第一件事（见 `.workflow/overseer.md`「工作模式与旋钮表」）。
   `$CLAUDE_EFFORT` 读出来是空的时追加（变量名可能随 CC 版本变了，读不到不能当作正常）：
   > （effort 读不到 ⚠️ —— 用 /effort 看一眼，或查 CC 版本说明）

   模式是 competition、effort 却低于 high 时追加：
   > （effort 实际为 medium ⚠️，比赛模式默认 high —— 会话内被调低了？用 /effort 调回，或重启）

   有同名例外满 2 次时追加：
   > （【例外:约定3】已 2 次 ⚠️ —— 列入下一次复审）

   `ctx-pointers.py` 有命中（退出码 3）时追加，并在本轮把命中的指针改成自足摘要（这些条目归档后指针必然悬空）：
   > （悬空指针 2 处 ⚠️，其中疑似在代码块/注释里 0 处：第 123 行「见「当前状态」」…）

   标了「疑似在代码块/注释里」的命中，**看原文判断，不凭标签**（标签在几种写法上已知会标错，见脚本头注释）：
   原文确实是引用的示例（如原样粘贴的闸门输出里出现的字样）才在复述里说明并留着，它随条目轮换进 `context_history.md` 后不再报；
   是真指针就照样改。

   `ctx-pointers.py` 退出码 0 时不另起一句，在复述的括号里带上「指针 0 处 / 查了第 a..b 行」。退出码 1 或 2 时追加：
   > （悬空指针检查没跑成 ⚠️：<它的 stderr>）

   sessions.md：`sessions-md rc=0` 且 grep 出了数字时不另起一句，括号里带上「sessions.md 空备注 N 行」。
   项目里还没有 sessions.md（印了「sessions.md 未生成」）时，括号里写「sessions.md 未生成，按来源算空备注 N 行」；
   `.workflow/overseer.md`「全局者 → 工作者」的交接序列里已经有登记那一步、文件却还没生成，说明那一步一直没人跑，照实告诉用户。下面三种追加：
   脚本不存在（印了「sessions-md.py 不存在」，这时 rc 是 2）：
   > （sessions.md 检查没跑成 ⚠️：~/.claude/scripts/sessions-md.py 不存在 —— 部署见 `.workflow/overseer.md`「K10 第三者（续）」的「部署」条）

   退出码非 0（1 = 拒绝：已有 sessions.md 解析不了、本项目 0 个会话等；2 = 用法错误或脚本打不开）：
   > （sessions.md 检查没跑成 ⚠️ rc=1：<它打印的最后一行>）

   退出码 0 却没 grep 出数字（脚本摘要的措辞变了）：
   > （sessions.md 空备注数没取到 ⚠️：<摘要末两行>）

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

   `context.md` ≥ 300 行时追加（`.workflow/overseer.md`「长度规则」的软上限）：
   > （context 334 行 / 31000 字符 ⚠️ 超软上限，下一轮决策前先清理：旧轮迁 `context_history.md`）

   ctx-size.py 印出「超线」时同样追加（字符线见 `.workflow/overseer.md`「长度规则」，软线、只提醒）：
   > （context 290 行 / 51283 字符 ⚠️ 超字符线 N（N 取自 ctx-size.py 输出的「字符线 N」），下一轮决策前先清理：旧轮迁 `context_history.md`）

   `context_history.md` ≥ 1800 行时追加：
   > （history 2407 行 ⚠️ 建议做一次阶段封存，见 `.workflow/overseer.md`「Phase 关闭时的归档操作」）

   **特例：`context_history.md` 不存在而 `context.md` 已超线** —— 说明三层历史机制
   在本项目从未启动过，历史一直堆在 `context.md` 里。这种漏法没有「变长」的过程可察觉，
   从第一天起就是那样。此时先建 `context_history.md` 再迁，别只做清理。

   本会话首次、且第 1 步的 `dmw-version.py check` 退出 3 时，再追加一句（把它列出的发现行带上）：
   > （工作流副本落后或本地改过 ⚠️：<dmw-version.py 的发现行> —— 要先升级吗?）

   退出 1 或 2（范围算不出 / 没找到模板根；它在 stderr 里说了原因）时改追加，不能当作「没有差异」：
   > （版本检查没跑成 ⚠️：<它的 stderr 第一行>）

   不是错误，是信号 —— 不阻塞本轮工作，阈值本身也是弹性的。但**行数这一段是必发的**：
   判定条件放在输出之后，不放在输出之前 —— 写成「超线才提」等于漏检时悄无声息，
   写成「无条件打印」则漏检表现为复述句里少一段，用户当场看得见。
4. **若工作者交付了完成阶段（有「关键决策点」四项）**：
   - **先跑 `python3 ~/.claude/scripts/handoff-check.py`**（只读，不带 `--fresh`）：它机械核对提交行与 sha、交接块三个标签与四个关键词、闸门里的 `rc=`、「当前状态」两行、工作树有无未提交改动、时间戳、交接块里有无行首 `workflow-mode:`；
     退出 3 就按它列的逐条退回；它不核对内容是否属实，下面各项照旧。脚本不存在时，照实告诉用户，按下面的文字手工核对
   - **先核对提交**：「完成情况」开头应是 `` 提交：`<sha>`； ``，且 `git cat-file -t <sha>` 输出 `commit`、
     `git merge-base --is-ancestor <sha> HEAD` 退出 0（不是 HEAD 祖先的 sha，第 2 步取 base 时会被略过）。
     有文件改动却没写 sha、sha 不是提交、或交接块里说改了的文件在 `git status --porcelain -- <这些文件>` 里仍列为未提交（`context.md` 除外）→
     **退回，要求先提交，本轮不放行**，后面几项不必再审。写「提交：无（<原因>）」的，核对确实没有文件改动后照常审
   - 核对四项：架构/接口变动、安全相关、偏离原计划、未解决的疑虑
   - 交接块里的「闸门结果」「spec 修正」两个字段，按 `.workflow/overseer.md`「全局者审查交接时」里「交接块里另外两个字段」处理：
     闸门结果核对原始输出、`rc=N` 与自报的通过/失败一致，对比上一轮找回归（有回归时「完成情况」紧跟「提交：…；」的第一句应写明），只有摘要或没写 rc 的退回补贴；
     标「可重跑」的闸门在 rc≠0、尾部计数与 rc 对不上、或 phase 关闭前自己重跑一次，只看退出码和计数行，平时不强制每轮重跑；
     没标的按「不可重跑」处理，并在本轮写「当前状态」时补标；
     spec 修正逐条确认确属笔误类，确认结果写进本轮全局者条目的「spec 修正确认」
   - 没有工具判定的质量项：核对「完成情况」里对判据清单（截图条件、可观察断言）的逐条回答，
     然后**自己读图 / 读产出** —— 这是最终闸门，不凭工作者的自报放行
   - 架构/接口变动、偏离原计划、未解决的疑虑三项非空时，按 `.workflow/overseer.md`「全局者审查交接时」那段处理
   - **若「安全相关」非空，或第 2 步预检退出码 1（退出码 2 修不好时同此）→ 必须做结构化安全审查**，凭报告判断，不得仅凭摘要放行：
     - 首选 invoke `critic` 子代理（`.claude/agents/critic.md`）对工作者点名的相关文件审查
     - 注意：它是项目级 agent，只有从项目目录启动 claude 才注册 —— 从 `/root` 起
       session 再 `cd` 进去会报 `Agent type 'critic' not found`(见 memory
       `dual-model-critic-discovery`)。此时**退用内置 `security-reviewer`**，
       约束只读 + 按 critic 的报告格式输出，本项目已有先例。
     - **两条路都不通时才停下来问，不允许因为拿不到 critic 就跳过这一步。**
   - 完成审查后，给方向或写决策到 context.md（时间戳先跑 `date '+%Y-%m-%d %H:%M'` 取）。
     放行代码时在「决策」里写「放行到 `<sha>`」，下一轮预检的 `<base>` 从这里取（第 2 步）。`<sha>` 取上面核对过的工作者提交，
     通常等于审查时的 `git rev-parse --short HEAD`；HEAD 比它新时仍写工作者那个，多出来的提交留给下一轮预检去扫。
     全局者自己实现、没有工作者提交时，取自己提交后的 `git rev-parse --short HEAD`。
     工作树里未提交的改动不能放行 —— 写不出一个真实提交的 sha，就是该退回
5. **若工作者触发切换（遇到无法决策的问题）**：
   - **先跑 `python3 ~/.claude/scripts/handoff-check.py`**（只读，不带 `--fresh`）：这种块没有「完成情况」，它按「问题 / 已尝试 / 需要决策」三个标签查，并查时间戳、「当前状态」两行、有无行首 `workflow-mode:`、这一轮有没有写出格式正确的新块（没写或标题写错会落回上一轮的旧块，它会报 H0）；**不查提交与工作树**（切换时常有未提交的半成品）。退出 3 就按它列的退回；脚本不存在时照实告诉用户
   - 阅读「问题 / 已尝试 / 需要决策 / 附带变动 / spec 修正」；spec 修正非空时同第 4 步逐条确认，结果写进本轮全局者条目的「spec 修正确认」
   - 交接块报「某条前提不成立」时（切换触发条件第 6 条）：核实后，把「当前状态」里原来那条「- [ ]」改成「⚠️ 已证伪」条目
     （沿用 WORKFLOW.md 模板的格式，`ctx-size.py` 按它认墓碑），列出受影响的决策 —— 工作者不改已有条目，这一步只能由你做
   - 安全：第 2 步预检退出码 1（或 2 修不好）时，同第 4 步做结构化安全审查。
     **预检退出码 0 不等于这一块与安全无关**：切换触发条件第 2 条（安全、性能相关的设计决策）切回时多半还没有代码，预检扫不到东西。
     涉及安全架构设计（认证/授权、密钥、加密、外部输入的边界等）时，按需 invoke `critic` 审设计说明和相关的现有文件（拿不到 critic 的退路同第 4 步）；
     命中 WORKFLOW.md「任务分流与升级规则」强制升级几类的，按那条由你直接产出核心实现，在任务清单里标「（全局者实现）」
   - 做决策，按全局者写入格式记入 context.md（时间戳先跑 `date '+%Y-%m-%d %H:%M'` 取）。
     切换块没有「提交」，本轮不写「放行到」：工作者切回前的改动，等它按完成阶段格式交接（带提交 sha）时随第 4 步一起审、一起放行。
     例外是你本轮自己实现并已提交的代码，按第 4 步末尾「全局者自己实现」那句取 sha
   - 说：「决策已写入，可切换回工作者继续。」

## 等价于

旧的手打切换话语：「工作者修改了内容，查看 context 文件」。语义相同，这是更便利的入口。
