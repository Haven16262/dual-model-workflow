#!/usr/bin/env bash
# Regression test for scripts/ctx-pointers.py (dangling pointers in context.md「本 Phase 历史」).
# Usage: bash test_ctx_pointers.sh
# Output: "checked N cases: all passed" or the failures; exit 1 on any failure.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
PY="$HERE/../ctx-pointers.py"
TPL="$HERE/../../templates/context.md"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
n=0; fail=0
c() { # name content rc_want regex [regex2]
  n=$((n+1))
  local f="$T/ctx-$1.md"; printf '%b' "$2" > "$f"
  local out rc; out=$(python3 "$PY" "$f" 2>&1); rc=$?
  if [ "$rc" = "$3" ] && printf '%s' "$out" | grep -qE -- "$4" && { [ -z "${5:-}" ] || printf '%s' "$out" | grep -qE -- "$5"; }; then :; else
    fail=$((fail+1)); echo "FAIL $1: rc=$rc want=$3 re=$4"; printf '%s\n' "$out" | tail -5 | sed 's/^/    /'; fi
}
H='## 当前状态\nx\n## 跨 Phase 关键约定\ny\n## 本 Phase 历史\n'
W='## [2026-10-19 10:00] 工作者 — a\n'
O='## [2026-10-19 11:00] 全局者 — b\n'
c empty      "$H<!-- 注释 -->\n\n_无，等首次交互后开始累积。_\n" 0 '^查了第 5\.\.8 行（「## 本 Phase 历史」整段逐行全查，0 条条目）；悬空指针 0 处，其中疑似在代码块/注释里 0 处$'
c clean      "$H$W**完成情况：** 做完了\n$O**决策：** 改用 X\n" 0 '2 条条目，首末条 2026-10-19 10:00\.\.2026-10-19 11:00）；悬空指针 0 处'
c see_state  "$H$W**完成情况：** 见当前状态→任务清单\n" 3 '悬空指针 1 处'
c see_quoted "$H$O**决策：** 详见「当前状态」的任务 2\n" 3 '第 7 行「见「当前状态」'
c same_above "$H$W| a | b |\n| c | 同上 |\n" 0 '悬空指针 0 处'
c same_prev  "$H$W**完成情况：** 同上一轮一样，通过\n" 0 '悬空指针 0 处'
c see_prev   "$H$W**完成情况：** 见上一条\n" 3 '「见上一条」'
c commit_sha "$H$W**完成情况：** 提交：\`a1b2c3d\`；做完了\n$O**决策：** 放行到 \`a1b2c3d\`\n" 0 '悬空指针 0 处'
c commit_none "$H$W**完成情况：** 提交：无（只读调研，没有文件改动）；见当前状态→任务清单\n" 3 '第 7 行「见当前状态」'
c fenced     "$H$W**闸门结果：**\n\`\`\`\n## not a heading 见当前状态\n\`\`\`\n" 3 '第 9 行「见当前状态」（疑似在代码块/注释里）'
c fence4     "$H$W\`\`\`\`\n\`\`\`\n同上\n\`\`\`\n\`\`\`\`\n" 0 '悬空指针 0 处'
c comment_ml "$H<!-- 一\n见当前状态\n-->\n$W" 3 '第 7 行「见当前状态」（疑似在代码块/注释里）'
c no_stamp   "$H## Phase 2 关闭\n总结\n" 0 '首末条 第 6 行「Phase 2 关闭」'
c crlf       "${H//\\n/\\r\\n}$W" 0 '1 条条目'
c h3_entry   "$H### [2026-08-26 07:47 +08:00] 工作者 → 全局者 — x\n见上一轮\n" 3 '首末条 2026-08-26 07:47.*悬空指针 1 处'
c preamble   "$H> 本 Phase 已归档，详见当前状态的说明\n\n$W" 3 '第 6 行「见当前状态」'
c heading    "$H## [2026-10-19 10:00] 工作者 — 见当前状态\n" 3 '悬空指针 1 处'
c fp_opinion "$H$W意见：当前状态没问题\n常见的当前状态机\n没见到问题，当前状态已恢复\n" 0 '悬空指针 0 处'
c inline_cmt "$H$W正文里写 \`<!--\` 的用法\n见当前状态→任务清单\n" 3 '悬空指针 1 处' '其中疑似在代码块/注释里 0 处'
c cmt_then   "$H$W<!-- x --> 见当前状态\n" 3 '悬空指针 1 处' '其中疑似在代码块/注释里 0 处'
c open_fence "$H$W\`\`\`\n见当前状态\n" 3 '第 8 行「见当前状态」（疑似'
c open_cmt   "$H$W<!-- 开头\n见当前状态\n" 3 '第 8 行「见当前状态」（疑似'
c no_section "## 当前状态\nx\n" 1 '标题有 0 个'
c two_sect   "$H$W$H" 1 '标题有 2 个'
c layout     "$H$W## 当前状态\n" 1 '段落布局认不出'
c layout2    "$H$W## 跨 Phase 关键约定\n" 1 '段落布局认不出'
c open_tilde "$H$W~~~\n见当前状态\n" 3 '第 8 行「见当前状态」（疑似'
c inline_fnc "$H$W\`\`\`pytest\`\`\` 通过\n见当前状态→任务清单\n\`\`\`pytest\`\`\` 通过\n" 3 '第 8 行「见当前状态」' '其中疑似在代码块/注释里 0 处'
c info_close "$H$W\`\`\`\n\`\`\`bash\n\`\`\`\n见当前状态\n" 3 '第 10 行「见当前状态」' '其中疑似在代码块/注释里 0 处'
c cmt_fence  "$H$W<!-- 例：\n\`\`\`\n-->\n见当前状态\n<!--\n\`\`\`\n-->\n" 3 '第 10 行「见当前状态」' '其中疑似在代码块/注释里 0 处'
c see_top    "$H$W**决策：** 规格见顶部任务清单\n" 3 '「见顶部」'
c gap14      "$H$W详见 \`context.md\`「当前状态」任务清单 1-4\n" 3 '悬空指针 1 处'
c gap16      "$H$W见一二三四五六七八九十一二三四五六当前状态\n" 3 '悬空指针 1 处'
c gap17      "$H$W见一二三四五六七八九十一二三四五六七当前状态\n" 0 '悬空指针 0 处'
c list_fence "$H- \`\`\`bash\n  ls\n  \`\`\`\n$W**完成情况：** 见当前状态→任务清单\n- \`\`\`bash\n  ls\n  \`\`\`\n" 3 '1 条条目.*悬空指针 1 处，其中疑似在代码块/注释里 0 处' '其中疑似在代码块/注释里 0 处'
c all_fenced "$H\`\`\`\n$W见当前状态\n\`\`\`\n" 3 '1 条条目.*悬空指针 1 处，其中疑似在代码块/注释里 1 处'
c dbl_cmt    "$H$W<!-- 注1 --> <!-- 注2\n\`\`\`\n-->\n**完成情况：** 见当前状态→任务清单\n<!-- 注3 --> <!-- 注4\n\`\`\`\n-->\n" 3 '第 10 行「见当前状态」' '其中疑似在代码块/注释里 0 处'
c reopen_cmt "$H$W<!-- 一\n--> <!-- 二\n\`\`\`\n-->\n见当前状态\n<!-- 三\n--> <!-- 四\n\`\`\`\n-->\n" 3 '第 11 行「见当前状态」' '其中疑似在代码块/注释里 0 处'
c cmt_fence1 "$H$W<!-- 注 --> \`\`\`\n见当前状态→任务清单\n\`\`\`bash\nls\n\`\`\`\n" 3 '第 8 行「见当前状态」' '其中疑似在代码块/注释里 0 处'
c list_close "$H$W\`\`\`markdown\n- \`\`\`\n\`\`\`\n见当前状态→任务清单\n\`\`\`\n- \`\`\`\n\`\`\`\n" 3 '第 10 行「见当前状态」' '其中疑似在代码块/注释里 0 处'
c tilde_del  "$H$W~~~废弃方案~~~\n见当前状态→任务清单\n~~~bash\nls\n~~~\n" 3 '第 8 行「见当前状态」' '其中疑似在代码块/注释里 0 处'
c cmt_head   "$H$W<!-- a --> ## 当前状态\nx\n" 1 '第 7 行.*段落布局认不出'
c crlf_list  "$(printf '%s' "$H$W\`\`\`markdown\n- \`\`\`\n\`\`\`\n见当前状态\n\`\`\`\n- \`\`\`\n\`\`\`\n" | sed 's/\\n/\\r\\n/g')" 3 '第 10 行「见当前状态」' '其中疑似在代码块/注释里 0 处'
P='**完成情况：** 见当前状态→任务清单，见顶部\n'
H2='## 当前状态\nx\n## 跨 Phase 关键约定\ny\n## 本 Phase 历史 <!-- 只留最近 1 对 -->\n'
c sect_cmt   "$H2$W见当前状态→任务清单\n" 3 '查了第 5\.\.7 行.*悬空指针 1 处'
c sect_cmt2  "$H2$W见当前状态→任务清单\n\`\`\`\n## 本 Phase 历史\n\`\`\`\n" 1 '标题有 2 个'
c sect_open  "## 当前状态\nx\n## 跨 Phase 关键约定\ny\n## 本 Phase 历史 <!-- 没闭合\n$W见当前状态\n\`\`\`\n## 本 Phase 历史\n\`\`\`\n" 1 '第 5 行.*起点认不准'
c sect_text  "## 当前状态\nx\n## 跨 Phase 关键约定\ny\n## 本 Phase 历史（Phase 3）\n$W见当前状态\n" 1 '起点认不准'
D='见当前状态\n\`\`\`\n## 本 Phase 历史\n\`\`\`\n'; X='## 当前状态\nx\n## 跨 Phase 关键约定\ny\n'
c near_sp    "$X  ## 本 Phase 历史\n$D" 1 '起点认不准'
c near_tab   "$X##\t本 Phase 历史\n$D" 1 '起点认不准'
c near_2sp   "$X##  本 Phase 历史\n$D" 1 '起点认不准'
c near_cmt   "$X## <!-- x --> 本 Phase 历史\n$D" 1 '起点认不准'
c near_setx  "$X本 Phase 历史\n---\n$D" 1 '起点认不准'
c near_h3    "$X### 本 Phase 历史\n$D" 1 '起点认不准'
c other_h3   "$H$W### 本 Phase 历史原文\n" 0 '悬空指针 0 处'
c prose_ok   "$H$W往「本 Phase 历史」追加一条\n" 0 '悬空指针 0 处'
c layout_cmt "$H$W## 当前状态 <!-- x -->\n" 1 '段落布局认不出'
c tilde_info "$H$W~~~bash ~/run.sh\necho ok\n~~~\n$P~~~bash ~/run.sh\necho ok\n~~~\n" 3 '第 10 行「见当前状态」：' '其中疑似在代码块/注释里 0 处'
# 下面 5 条的标签已知会错（头注释「已知限制·标签」），只断言命中与退出码，不断言标签
c list_cmt   "$H$W- <!--\n  \`\`\`\n  -->\n$P- <!--\n  \`\`\`\n  -->\n" 3 '第 10 行「见当前状态」'
c cmt_text   "$H$W<!-- 注1 --> 说明 <!-- 注2\n\`\`\`\n-->\n$P<!-- 注1 --> 说明 <!-- 注2\n\`\`\`\n-->\n" 3 '第 10 行「见当前状态」'
c empty_cmt  "$H$W<!--->\n$P<!-- x -->\n" 3 '第 8 行「见当前状态」'
c tab_cmt    "$H$W\t<!-- 示例\n$P-->\n" 3 '第 8 行「见当前状态」'
c indent4    "$H$W    \`\`\`\n见当前状态\n    \`\`\`\n" 3 '第 8 行「见当前状态」'
c ideo_space "$H$W　\`\`\`\n见当前状态\n　\`\`\`\n" 3 '第 8 行「见当前状态」：' '其中疑似在代码块/注释里 0 处'
# 不变式：退出 0 ⇒ 标题之后每一行都查过。把各种代码块/注释写法拼成一份，往标题之后的每一行逐个塞指针，
# 每个位置都必须退出 3 并报出那一行（在代码块/注释里也一样）。
n=$((n+1)); B="$T/base.md"
printf '%b' "$H$W\`\`\`markdown\n- \`\`\`\n\`\`\`\n<!-- 1 --> <!-- 2\n\`\`\`\n-->\n~~~bash ~/a\n~~~\n- <!--\n  \`\`\`\n  -->\n<!-- a --> 说明 <!-- b\n\`\`\`\n-->\n<!--->\n\t<!-- c\n    \`\`\`\n　\`\`\`\n~~~废弃~~~\n<!-- x --> \`\`\`\n\`\`\`pytest\`\`\` 通过\n正文\n" > "$B"
total=$(wc -l < "$B"); bad=0
for k in $(seq 6 "$total"); do
  awk -v k="$k" 'NR==k{$0=$0" 见当前状态"}1' "$B" > "$T/pos.md"
  out=$(python3 "$PY" "$T/pos.md" 2>&1); rc=$?
  [ "$rc" = 3 ] && printf '%s' "$out" | grep -q "第 $k 行「见当前状态」" || { bad=$((bad+1)); echo "FAIL invariant: 第 $k 行 rc=$rc"; }
done
out=$(python3 "$PY" "$B" 2>&1); rc=$?
[ "$rc" = 0 ] || { bad=$((bad+1)); echo "FAIL invariant: 基底本身 rc=$rc（应为 0）"; }
[ "$bad" = 0 ] || fail=$((fail+1))
n=$((n+1)); out=$(python3 "$PY" 2>&1); rc=$?
[ "$rc" = 2 ] || { fail=$((fail+1)); echo "FAIL no_arg: rc=$rc"; }
n=$((n+1)); out=$(python3 "$PY" "$T/missing.md" 2>&1); rc=$?
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q '读取失败' || { fail=$((fail+1)); echo "FAIL missing: rc=$rc $out"; }
n=$((n+1)); printf '## 本 Phase 历史\n\377\376\n' > "$T/bad.md"; out=$(python3 "$PY" "$T/bad.md" 2>&1); rc=$?
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q '读取失败' || { fail=$((fail+1)); echo "FAIL bad_utf8: rc=$rc $out"; }
n=$((n+1)); out=$(python3 "$PY" "$TPL" 2>&1); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q '0 条条目' || { fail=$((fail+1)); echo "FAIL template: rc=$rc $out"; }
if [ "$fail" -eq 0 ]; then echo "checked $n cases: all passed"; exit 0; fi
echo "checked $n cases: $fail failed"; exit 1
