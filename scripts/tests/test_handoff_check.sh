#!/usr/bin/env bash
# Regression test for scripts/handoff-check.py. Usage: bash test_handoff_check.sh
# 每条规则 H1–H7 至少一个「报」和一个「不报」的用例；范围算不出（退出 1）、用法错误（退出 2）也各有一例。
# Output: "checked N cases: all passed" or failures; exit 1 on any failure.
set -u
HERE=$(cd "$(dirname "$0")" && pwd); PY="${HANDOFF_PY:-$HERE/../handoff-check.py}"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
n=0; fail=0
NOW="2026-11-18 12:00"
chk() { # name rc_want regex(or '-' = 不匹配任何) -- args...
  local name=$1 want=$2 re=$3; shift 4
  n=$((n+1)); out=$(cd "$PROJ" && python3 "$PY" "$@" 2>&1); rc=$?
  if [ "$rc" = "$want" ] && { [ "$re" = - ] || printf '%s' "$out" | grep -qE -- "$re"; }; then :; else
    fail=$((fail+1)); echo "FAIL $name: rc=$rc want=$want re=$re"; printf '%s\n' "$out" | tail -4 | sed 's/^/    /'; fi
}
nochk() { # name regex -- args...  : 输出里不许出现 regex（rc 不限）
  local name=$1 re=$2; shift 3
  n=$((n+1)); out=$(cd "$PROJ" && python3 "$PY" "$@" 2>&1)
  if printf '%s' "$out" | grep -qE -- "$re"; then fail=$((fail+1)); echo "FAIL $name: 不该出现 $re"; printf '%s\n' "$out" | tail -4 | sed 's/^/    /'; fi
}
state() { printf '## 当前状态\n**阶段:** P\n**未验证的前提:** 无\n**backlog(未决项):** 无\n\n'; }
mkproj() { # 建一个带提交的 git 项目，$PROJ 指向它；HEAD sha 放 $SHA
  PROJ=$(mktemp -d -p "$T"); (cd "$PROJ" && git init -q . && echo a > f.txt && git add f.txt && git commit -qm init) ; SHA=$(cd "$PROJ" && git rev-parse --short HEAD)
}
full_block() { # $1=sha  $2=时间  → 完成阶段块
  cat <<EOB
## [$2] 工作者 — 做完了
**完成情况：** 提交：\`$1\`；做了 X
**任务进度：**
- [x] 任务 1
**闸门结果：**
- 单测（可重跑）：\`bash t.sh\` —— rc=0；本轮通过；上一轮首次
**spec 修正：** 无
**关键决策点：**
- 架构/接口变动：无
- 安全相关：无
- 偏离原计划：无
- 未解决的疑虑：无
EOB
}

# ---- H 全过 ----
mkproj; { echo "# 项目"; state; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 11:30"; } > "$PROJ/context.md"
chk pass-all 0 '发现 0 项' -- --now "$NOW"
chk pass-all-prints-scope 0 '查了 [0-9]+ 项（H0 .*H1 时间戳、H2 提交行 \+ git 核对.*H7 工作树' -- --now "$NOW"
nochk no-nothing-new-sentence '没有新东西|无新发现' -- --now "$NOW"
chk pass-fresh 0 '发现 0 项' -- --now "$NOW" --fresh 120

# ---- H1 ----
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 13:00"; } > "$PROJ/context.md"
chk h1-future 3 'H1 交接块时间.*晚于现在' -- --now "$NOW"
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 11:50"; } > "$PROJ/context.md"
nochk h1-within-skew-ok "⚠ H1" -- --now "$NOW"
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 08:00"; } > "$PROJ/context.md"
chk h1-fresh-old 3 'H1 .*超过 120 分钟' -- --now "$NOW" --fresh 120
chk h1-old-ok-without-fresh 0 '发现 0 项' -- --now "$NOW"
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo "## [2026-11-18 11:40] 全局者 — 决策"; echo "x"; echo; full_block "$SHA" "2026-11-18 11:00"; } > "$PROJ/context.md"
chk h1-before-previous 3 'H1 交接块时间.*早于上一条' -- --now "$NOW"
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo "## [2026-11-18 11:40 CST] 全局者 — 决策"; echo "x"; echo; full_block "$SHA" "2026-11-18 11:00"; } > "$PROJ/context.md"
chk h1-different-tz-not-compared 0 '发现 0 项' -- --now "$NOW"
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo "## [2026-13-45 99:99] 工作者 — x"; echo "**完成情况：** 提交：无（只读调研）"; } > "$PROJ/context.md"
chk h1-unparseable 3 'H1 标题里的时间戳解析不了' -- --now "$NOW"

# ---- H2 ----
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 11:30" | sed 's/提交：`[0-9a-f]*`；/做了 X；/'; } > "$PROJ/context.md"
chk h2-no-commit-line 3 'H2 「完成情况」里没有「提交' -- --now "$NOW"
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 11:30" | sed 's/提交：`[0-9a-f]*`；/提交：无（只读调研，没有文件改动）；/'; } > "$PROJ/context.md"
chk h2-no-commit-with-reason-ok 0 '发现 0 项' -- --now "$NOW"
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; full_block "deadbee" "2026-11-18 11:30"; } > "$PROJ/context.md"
chk h2-bogus-sha 3 'H2 提交 `deadbee` 不是这个仓库里的 commit' -- --now "$NOW"
chk h2-bogus-sha-no-git 0 '跳过 .*H2 提交 sha 与祖先关系' -- --now "$NOW" --no-git
(cd "$PROJ" && git checkout -q -b side && echo b > g.txt && git add g.txt && git commit -qm side && git checkout -q - ) ; SIDE=$(cd "$PROJ" && git rev-parse --short side)
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; full_block "$SIDE" "2026-11-18 11:30"; } > "$PROJ/context.md"
chk h2-not-ancestor 3 "H2 提交 \`$SIDE\` 不是 HEAD 的祖先" -- --now "$NOW"

# ---- H3 / H4 ----
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 11:30" | grep -v 'spec 修正'; } > "$PROJ/context.md"
chk h3-missing-spec 3 'H3 完成阶段块缺「spec 修正」' -- --now "$NOW"
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 11:30" | grep -v '偏离原计划\|未解决的疑虑'; } > "$PROJ/context.md"
chk h3-missing-keywords 3 'H3 「关键决策点」之后缺：偏离原计划、未解决的疑虑' -- --now "$NOW"
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 11:30" | grep -v '闸门结果\|单测'; } > "$PROJ/context.md"
chk h3-missing-gate-label 3 'H3 完成阶段块缺「闸门结果」' -- --now "$NOW"
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 11:30" | sed 's/ —— rc=0；/ —— 本轮通过；/'; } > "$PROJ/context.md"
chk h4-no-rc 3 'H4 「闸门结果」不是「无」，却一处 rc=' -- --now "$NOW"
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 11:30" | sed '/单测/d; s/^\*\*闸门结果：\*\*$/**闸门结果：** 无/'; } > "$PROJ/context.md"
chk h4-gate-none-ok 0 '发现 0 项' -- --now "$NOW"
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 11:30" | sed 's/ —— rc=0；/ —— rc = 1；/'; } > "$PROJ/context.md"
chk h4-rc-with-spaces-ok 0 '发现 0 项' -- --now "$NOW"

# ---- H5 ----
printf '# 项目\n%s## 本 Phase 历史\n\n## [2026-11-18 11:30] 工作者 → 全局者\n**问题：** a\n**已尝试：** b\n**需要决策：** c\n**附带变动：** 无\n**spec 修正：** 无\n' "$(state)" > "$PROJ/context.md"
chk h5-ok 0 '非完成阶段格式.*发现 0 项' -- --now "$NOW"
printf '# 项目\n%s## 本 Phase 历史\n\n## [2026-11-18 11:30] 工作者 → 全局者\n**问题：** a\n**需要决策：** c\n' "$(state)" > "$PROJ/context.md"
chk h5-missing-tried 3 'H5 .*缺「已尝试」' -- --now "$NOW"

# ---- H6 ----
{ echo "# 项目"; printf '## 当前状态\n**阶段:** P\n**未验证的前提:** 无\n\n'; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 11:30"; } > "$PROJ/context.md"
chk h6-missing-backlog 3 'H6 .*没有「backlog」' -- --now "$NOW"
{ echo "# 项目"; printf '## 当前状态\n**阶段:** P\n**backlog(未决项):** 无\n\n'; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 11:30"; } > "$PROJ/context.md"
chk h6-missing-premise 3 'H6 .*没有「未验证的前提」' -- --now "$NOW"
# 「未验证的前提」只出现在历史段、不在当前状态段：不算
{ echo "# 项目"; printf '## 当前状态\n**阶段:** P\n\n'; echo "## 本 Phase 历史"; echo "未验证的前提 backlog"; echo; full_block "$SHA" "2026-11-18 11:30"; } > "$PROJ/context.md"
chk h6-only-in-history-not-counted 3 'H6' -- --now "$NOW"

# 模板原样的「当前状态」：只有 HTML 注释（注释里写着「backlog 与未验证的前提」），没有条目行 → 必须报（SMOKE-wp5 F1）
TPL="$HERE/../../templates/context.md"
tpl_state() { awk '/^## 当前状态/{f=1} f&&/^## /&&!/^## 当前状态/{exit} f' "$TPL"; }
{ echo "# 项目"; tpl_state; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 11:30"; } > "$PROJ/context.md"
chk h6-template-comment-only 3 'H6 .*没有「backlog」' -- --now "$NOW"
chk h6-template-comment-only-premise 3 'H6 .*没有「未验证的前提」' -- --now "$NOW"
# 多行注释里行首写着标签行：仍是注释，不算
{ echo "# 项目"; printf '## 当前状态\n<!-- 示例：\n**未验证的前提:** 无\n**backlog(未决项):** 无\n-->\n**阶段:** P\n\n'; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 11:30"; } > "$PROJ/context.md"
chk h6-label-inside-comment-not-counted 3 'H6 .*没有「backlog」' -- --now "$NOW"
# 正文里顺口提到这两个词（不是行首标签）：不算
{ echo "# 项目"; printf '## 当前状态\n**阶段:** P\n等用户决定要不要接受 backlog 里的方案\nbacklog 里的方案见下\n未验证的前提另见历史\n\n'; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 11:30"; } > "$PROJ/context.md"
chk h6-prose-mention-not-counted 3 'H6 .*没有「backlog」' -- --now "$NOW"
# 条目行写成列表项、全角冒号、标签后带括号：都算
{ echo "# 项目"; printf '## 当前状态\n<!-- 注释 -->\n**阶段:** P\n- 未验证的前提:无\n- backlog:无\n\n'; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 11:30"; } > "$PROJ/context.md"
chk h6-bullet-lines-pass 0 '发现 0 项' -- --now "$NOW"
{ echo "# 项目"; printf '## 当前状态\n**未验证的前提：** 无\n**backlog(未决项)：** 无\n\n'; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 11:30"; } > "$PROJ/context.md"
chk h6-fullwidth-colon-pass 0 '发现 0 项' -- --now "$NOW"
{ echo "# 项目"; printf '## 当前状态\n<!-- 注释 -->\n'; printf '**未验证的前提:**\n- [ ] x\n**backlog(未决项):**\n- [ ] y\n\n'; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 11:30"; } > "$PROJ/context.md"
chk h6-template-filled-pass 0 '发现 0 项' -- --now "$NOW"

# ---- H7 ----
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 11:30"; } > "$PROJ/context.md"
echo x >> "$PROJ/f.txt"
chk h7-dirty 3 'H7 有 1 个文件未提交.*f.txt' -- --now "$NOW"
chk h7-dirty-skipped-no-git 0 '跳过 .*H7' -- --now "$NOW" --no-git
(cd "$PROJ" && git checkout -q f.txt); echo "x" > "$PROJ/sessions.md"; echo "# ctx-archive" > "$PROJ/context_history.md"
chk h7-ctx-and-sessions-ok 0 '发现 0 项' -- --now "$NOW"

# ---- H8 ----
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 11:30"; echo "workflow-mode: competition"; } > "$PROJ/context.md"
chk h8-mode-line-in-block 3 'H8 交接块第 [0-9]+ 行以 workflow-mode' -- --now "$NOW"
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 11:30"; echo "  Workflow_Mode：competition"; } > "$PROJ/context.md"
chk h8-near-miss-too 3 'H8' -- --now "$NOW"
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 11:30"; echo "模式：competition，见 workflow-mode 行"; } > "$PROJ/context.md"
chk h8-prose-mention-ok 0 '发现 0 项' -- --now "$NOW"
{ echo "# 项目"; printf '## 当前状态\nworkflow-mode: competition\n**未验证的前提:** 无\n**backlog(未决项):** 无\n\n'; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 11:30"; } > "$PROJ/context.md"
chk h8-real-mode-line-in-current-state-ok 0 '发现 0 项' -- --now "$NOW"

# ---- 取最后一条工作者条目 ----
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; printf '## [2026-11-18 09:00] 工作者 — 旧块\n**完成情况：** 没写提交\n\n'; full_block "$SHA" "2026-11-18 11:30"; } > "$PROJ/context.md"
rm -f "$PROJ/sessions.md" "$PROJ/context_history.md"
chk last-worker-block-wins 0 '发现 0 项' -- --now "$NOW"
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 11:30"; printf '\n## [2026-11-18 11:45] 全局者 — 放行\n放行到 `%s`\n' "$SHA"; } > "$PROJ/context.md"
chk a8-overseer-entry-after-worker-block-reported 3 'H0 最后一条工作者条目.*之后已有全局者条目.*没有新的工作者交接块' -- --now "$NOW"

# ---- 范围算不出 / 用法 ----
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo "## [2026-11-18 11:45] 全局者 — 决策"; } > "$PROJ/context.md"
chk no-worker-entry 1 '没有工作者条目' -- --now "$NOW"
{ echo "# 项目"; echo "## 本 Phase 历史"; full_block "$SHA" "2026-11-18 11:30"; } > "$PROJ/context.md"
chk no-current-state 1 '没有「## 当前状态」' -- --now "$NOW"
chk missing-file 1 '找不到' -- nope.md
chk bad-flag 2 'handoff-check' -- --bogus
chk bad-now 2 'handoff-check' -- --now notatime
chk two-paths 2 'handoff-check' -- a.md b.md


# ======================= 复查第 1 轮（A4 与建议项）=======================
mkproj
# ---- A4a：代码围栏里的 `## ` 行不当条目边界（git status -sb 的第一行就是 ## main...origin/main）----
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo
  full_block "$SHA" "2026-11-18 11:30" | sed '/^\*\*闸门结果/,/^\*\*spec/{/^\*\*spec/!b};/^\*\*spec 修正/i\
```\
## main...origin/main\
 M f.txt\
```'
} > "$PROJ/context.md"
chk a4-fenced-hash-line-not-a-boundary 0 '发现 0 项' -- --now "$NOW"
# 围栏里的 ## 之后还有 spec 修正 / 关键决策点：截断就会误报 H3
nochk a4-no-false-h3 '⚠ H3' -- --now "$NOW"
# 反例：围栏外的真 `## ` 行仍然截断（后面的内容不算这个块）
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 11:30" | sed '/^\*\*spec 修正/i\
## 随手写的二级标题'; } > "$PROJ/context.md"
chk a4-real-heading-still-truncates 3 'H3 完成阶段块缺「spec 修正」' -- --now "$NOW"
# 围栏里的假标题行（形如 `## [时间] 工作者`）不被当成「最后一条工作者条目」
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 11:30"; printf '```\n## [2026-11-18 11:59] 工作者 — 示例里的\n```\n'; } > "$PROJ/context.md"
chk a4-fenced-fake-header-ignored 0 '11:30' -- --now "$NOW"

# ---- A4b：git 在 context.md 所在目录跑，不在当前目录 ----
mkproj; OTHER=$PROJ; (cd "$OTHER" && echo o > only-other.txt && git add only-other.txt && git commit -qm other-only); OSHA=$(cd "$OTHER" && git rev-parse --short HEAD)   # 另一个仓库：context.md 在这里，提交 $OSHA 只存在于这个仓库
mkproj; MINE=$PROJ; (cd "$MINE" && echo m > only-mine.txt && git add only-mine.txt && git commit -qm mine-only); SHA=$(cd "$MINE" && git rev-parse --short HEAD)   # 当前目录的仓库：没有 $OSHA；$SHA 只存在于这里
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; full_block "$OSHA" "2026-11-18 11:30"; } > "$OTHER/context.md"
PROJ=$MINE; chk a4-git-runs-in-context-dir 0 '发现 0 项' -- "$OTHER/context.md" --now "$NOW"
# 反过来：sha 只在当前目录的仓库里，context.md 在别处 → 报 H2（查的是 context.md 所在仓库）
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 11:30"; } > "$OTHER/context.md"
chk a4-wrong-repo-sha-reported 3 'H2 提交' -- "$OTHER/context.md" --now "$NOW"
# 工作树：当前目录脏、context.md 所在仓库干净 → H7 不报
echo x >> "$MINE/f.txt"; { echo "# 项目"; state; echo "## 本 Phase 历史"; echo; full_block "$OSHA" "2026-11-18 11:30"; } > "$OTHER/context.md"
chk a4-h7-checks-context-repo-not-cwd 0 '发现 0 项' -- "$OTHER/context.md" --now "$NOW"
(cd "$MINE" && git checkout -q f.txt)

# ---- B3：H7 只对完成阶段块查（非完成块 + 脏工作树不报）----
mkproj
printf '# 项目\n%s## 本 Phase 历史\n\n## [2026-11-18 11:30] 工作者 → 全局者\n**问题：** a\n**已尝试：** b\n**需要决策：** c\n' "$(state)" > "$PROJ/context.md"
echo wip >> "$PROJ/f.txt"
chk b3-noncomplete-dirty-tree-no-h7 0 '发现 0 项' -- --now "$NOW"
nochk b3-noncomplete-no-h7-line 'H7 有' -- --now "$NOW"
chk b3-noncomplete-says-h7-skipped 0 '跳过 1 项（H7 工作树（非完成阶段块不查' -- --now "$NOW"
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 11:30"; } > "$PROJ/context.md"
chk b3-complete-dirty-tree-still-h7 3 'H7 有 1 个文件未提交' -- --now "$NOW"
(cd "$PROJ" && git checkout -q f.txt)

# ---- A'：H4 ----
# 「无（原因）」写法与 H2 一致，视为没有闸门
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 11:30" | sed '/单测/d; s/^\*\*闸门结果：\*\*$/**闸门结果：** 无（只读调研，没有可跑的闸门）/'; } > "$PROJ/context.md"
chk ap-h4-none-with-reason-ok 0 '发现 0 项' -- --now "$NOW"
# 闸门输出里有粗体短语，不能在那里截断、漏掉后面的 rc=
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo
  full_block "$SHA" "2026-11-18 11:30" | sed 's/^- 单测（可重跑）：.*$/**说明：** 下面是原始输出\
- 单测（可重跑）：`bash t.sh` —— rc=0；本轮通过/'; } > "$PROJ/context.md"
chk ap-h4-bold-phrase-inside-gate-does-not-truncate 0 '发现 0 项' -- --now "$NOW"

# ---- A'：H1 时区后缀 ----
export TZ=Asia/Shanghai
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 04:00 UTC"; } > "$PROJ/context.md"      # = 本机 12:00
chk ap-h1-utc-suffix-converted-not-future 0 '发现 0 项' -- --now "$NOW" --fresh 120
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 12:00 UTC"; } > "$PROJ/context.md"      # = 本机 20:00，真的在未来
chk ap-h1-utc-suffix-real-future-caught 3 'H1 交接块时间.*UTC.*晚于现在' -- --now "$NOW"
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 11:30 +08:00"; } > "$PROJ/context.md"
chk ap-h1-offset-suffix-ok 0 '发现 0 项' -- --now "$NOW" --fresh 120
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 19:00 CST"; } > "$PROJ/context.md"
chk ap-h1-ambiguous-suffix-not-compared 0 '跳过 1 项（H1 与现在比较（标题时区后缀「CST」认不出' -- --now "$NOW" --fresh 120
unset TZ


# ---- A8：最后一条工作者条目之后已有别的条目 → 落回旧块，要报 ----
mkproj
# 上一轮已通过的旧块 + 全局者放行 + 工作者这一轮忘了写 / 标题写错
oldblk() { full_block "$SHA" "2026-11-18 09:00"; printf '\n## [2026-11-18 09:30] 全局者 — 放行\n放行到 `%s`\n\n' "$SHA"; }
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; oldblk; } > "$PROJ/context.md"
chk a8-forgot-new-block 3 'H0 .*之后已有全局者条目' -- --now "$NOW"
chk a8-forgot-new-block-also-without-fresh 3 'H0' -- --now "$NOW"
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; oldblk; full_block "$SHA" "2026-11-18 11:30" | sed 's/^## \[\(.*\)\] 工作者/## [\1] 做完了/'; } > "$PROJ/context.md"
chk a8-title-without-role 3 'H0 .*像交接块的标题，但认不出是工作者条目' -- --now "$NOW"
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; oldblk; full_block "$SHA" "2026-11-18 11:30" | sed 's/^## \[\(.*\)\] 工作者/#### [\1] 工作者/'; } > "$PROJ/context.md"
chk a8-four-hashes 3 'H0 .*认不出是工作者条目' -- --now "$NOW"
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; oldblk; full_block "$SHA" "2026-11-18 11:30" | sed 's/^## \[\(.*\)\] 工作者/## \1 工作者/'; } > "$PROJ/context.md"
chk a8-missing-brackets 3 'H0 .*认不出是工作者条目' -- --now "$NOW"
# 正常：全局者放行之后，工作者写了格式正确的新块 → 不报 H0
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; oldblk; full_block "$SHA" "2026-11-18 11:30"; } > "$PROJ/context.md"
chk a8-new-block-ok 0 '发现 0 项' -- --now "$NOW"
nochk a8-new-block-no-h0 '⚠ H0' -- --now "$NOW"
# 围栏里像标题的行不算
{ echo "# 项目"; state; echo "## 本 Phase 历史"; echo; full_block "$SHA" "2026-11-18 11:30"; printf '```\n#### [2026-11-18 11:59] 示例\n```\n'; } > "$PROJ/context.md"
chk a8-fenced-example-heading-ignored 0 '发现 0 项' -- --now "$NOW"

if [ "$fail" = 0 ]; then echo "checked $n cases: all passed"; else echo "checked $n cases: $fail failed"; exit 1; fi
