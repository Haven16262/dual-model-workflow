#!/usr/bin/env bash
# Unit tests for k10-watch.py / k10-stop-gate.py / k10-subagent-report.py.
# A stub `claude` (K10_CLAUDE) records argv/cwd/stdin; no model is called.
# Output: "checked N cases: all passed" or failures; exit 1 on failure.
set -u
S=$(cd "$(dirname "$0")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
n=0; fail=0; OUT=""; RC=0
expect() { # name condition (eval'd)
  local name=$1; shift
  n=$((n+1))
  if ! eval "$@"; then fail=$((fail+1)); echo "FAIL $name"; printf '%s\n' "$OUT" | tail -6 | sed 's/^/    /'; fi
}
cat > "$T/claude" <<'STUB'
#!/bin/sh
d="${K10_STUB_LOG:?}"; i=$(ls "$d" | wc -l)
{ echo "ARGS: $*"; echo "CWD: $(pwd)"; echo "---"; cat; } > "$d/call-$i.txt"
case "$*" in *SendMessage*) echo "SENT" ;; *) [ -n "${K10_STUB_SLEEP:-}" ] && sleep "$K10_STUB_SLEEP"; [ -n "${K10_STUB_FAIL:-}" ] && { echo boom >&2; exit 3; }; printf 'S1 测试意见\nS2 另一条\n' ;; esac
STUB
chmod +x "$T/claude"
mkproj() { # dir mode
  local d="$1"; mkdir -p "$d/.workflow/templates" "$d/rules"
  printf '# ctx\n%s\n' "${2:+workflow-mode: $2}" > "$d/context.md"
  echo "SKEPTIC TEMPLATE" > "$d/.workflow/templates/skeptic.md"
  echo "PROPOSER TEMPLATE" > "$d/.workflow/templates/proposer.md"
  echo "rule text" > "$d/rules/r.md"
}
cfg() { printf '%s\n' "$2" > "$1/.workflow/k10.json"; }
run_watch() { # proj today logtag [env...]
  local p=$1 d=$2 tag=$3; shift 3
  mkdir -p "$T/log-$tag"
  OUT=$(env K10_STUB_LOG="$T/log-$tag" K10_CLAUDE="$T/claude" K10_TODAY="$d" "$@" python3 "$S/k10-watch.py" "$p" 2>&1); RC=$?
}
ROLES='"roles":{"skeptic":{"template":".workflow/templates/skeptic.md"},"proposer":{"template":".workflow/templates/proposer.md","isolated":true,"inputs":["rules/r.md"]}}'

# 1 no k10.json -> exit 2, says why
P=$T/p1; mkproj "$P" competition
run_watch "$P" 2026-10-01 a
expect nocfg '[ $RC = 2 ] && grep -q "缺 .workflow/k10.json" <<<"$OUT"'
# 2 invalid mode -> exit 2
P=$T/p2; mkproj "$P" 比赛; echo '{}' > "$P/.workflow/k10.json"
run_watch "$P" 2026-10-01 b
expect badmode '[ $RC = 2 ] && grep -q "模式行非法" <<<"$OUT"'
# 3 calendar: not due / due fires once with report + doorbell / not again
P=$T/p3; mkproj "$P" competition
cfg "$P" '{"overseer_prefix":"x-overseer-","calendar":[{"id":"c1","date":"2026-10-02","roles":["skeptic"]}],'"$ROLES"'}'
run_watch "$P" 2026-10-01 c
expect cal_notdue '[ $RC = 0 ] && grep -q "查了 1 个触发条件.*触发 0 个" <<<"$OUT" && [ -z "$(ls "$T/log-c")" ]'
run_watch "$P" 2026-10-02 d
expect cal_due '[ $RC = 0 ] && grep -q "触发 1 个" <<<"$OUT" && ls "$P"/.workflow/reports/*-skeptic-c1.md >/dev/null 2>&1 && grep -q "门铃：已送达" <<<"$OUT"'
expect cal_args 'grep -q -- "--model opus --effort high --permission-mode default --allowedTools Read,Grep,Glob,WebSearch,WebFetch" "$T/log-d/call-0.txt" && grep -q "CWD: $P" "$T/log-d/call-0.txt"'
expect cal_template 'grep -q "SKEPTIC TEMPLATE" "$T/log-d/call-0.txt" && grep -q "日历召唤 c1" "$T/log-d/call-0.txt"'
expect cal_report_body 'grep -q "S1 测试意见" "$P"/.workflow/reports/*-skeptic-c1.md'
expect doorbell_tools 'grep -q -- "--allowedTools ListAgents,SendMessage" "$T/log-d/call-1.txt" && grep -q "x-overseer-" "$T/log-d/call-1.txt"'
run_watch "$P" 2026-10-03 e
expect cal_once '[ $RC = 0 ] && grep -q "触发 0 个" <<<"$OUT"'
# 4 k9 stall (rate rule with leaderboard): too few packs / fires / waits for N new packs
P=$T/p4; mkproj "$P" competition
cfg "$P" '{"overseer_prefix":"x-overseer-","k9":{"N":3,"slots_per_day":3,"end_date":"2026-10-03","target_rank":2,"roles":["skeptic"]},'"$ROLES"'}'
printf 'rank\tteam\tscore\tsubmissions\tbest_date\n1\ta\t900\t20\tx\n2\tb\t890\t10\tx\n3\tc\t800\t1\tx\n' > "$P/.workflow/leaderboard.tsv"
printf 'date\tpkg\tscore\nd\tp\t700\nd\tp\t750\nd\tp\t800\n' > "$P/.workflow/scores.tsv"
run_watch "$P" 2026-10-01 f
expect stall_too_few '[ $RC = 0 ] && grep -q "触发 0 个" <<<"$OUT"'
printf 'd\tp\t801\nd\tp\t801\nd\tp\t802\n' >> "$P/.workflow/scores.tsv"
run_watch "$P" 2026-10-01 g
expect stall_fire '[ $RC = 0 ] && grep -q "触发 1 个" <<<"$OUT" && ls "$P"/.workflow/reports/*-skeptic-stall-6.md >/dev/null 2>&1'
run_watch "$P" 2026-10-01 h
expect stall_wait_N '[ $RC = 0 ] && grep -q "触发 0 个" <<<"$OUT"'
# 5 external position: below median of low-submission teams fires once (edge)
P=$T/p5; mkproj "$P" competition
cfg "$P" '{"overseer_prefix":"x-overseer-","k9":{"N":50,"slots_per_day":3,"end_date":"2026-10-03","ext_k":5,"roles":["skeptic"]},'"$ROLES"'}'
printf 'rank\tteam\tscore\tsubmissions\tbest_date\n1\ta\t900\t2\tx\n2\tb\t880\t3\tx\n3\tc\t700\t30\tx\n' > "$P/.workflow/leaderboard.tsv"
printf 'date\tpkg\tscore\nd\tp\t850\n' > "$P/.workflow/scores.tsv"
run_watch "$P" 2026-10-01 i
expect pos_fire '[ $RC = 0 ] && grep -q "触发 1 个" <<<"$OUT" && grep -rq "外部位置" "$P/.workflow/reports/"'
run_watch "$P" 2026-10-01 j
expect pos_edge '[ $RC = 0 ] && grep -q "触发 0 个" <<<"$OUT"'
# 6 fixed_X fallback without leaderboard; neither computable -> exit 2
P=$T/p6; mkproj "$P" competition
cfg "$P" '{"overseer_prefix":"x-overseer-","k9":{"N":2,"fixed_X":5,"roles":["skeptic"]},'"$ROLES"'}'
printf 'date\tpkg\tscore\nd\tp\t10\nd\tp\t12\nd\tp\t13\n' > "$P/.workflow/scores.tsv"
run_watch "$P" 2026-10-01 k
expect fixedX '[ $RC = 0 ] && grep -q "触发 1 个" <<<"$OUT" && grep -rq "合计增量 3.00 < X=5" "$P/.workflow/reports/"'
P=$T/p7; mkproj "$P" competition
cfg "$P" '{"overseer_prefix":"x-overseer-","k9":{"N":2,"roles":["skeptic"]},'"$ROLES"'}'
printf 'date\tpkg\tscore\nd\tp\t10\nd\tp\t12\nd\tp\t13\n' > "$P/.workflow/scores.tsv"
run_watch "$P" 2026-10-01 l
expect k9_uncomputable '[ $RC = 2 ] && grep -q "算不出" <<<"$OUT"'
expect k9_error_recorded 'grep -q "\"last_k9_error\": \"20" "$P/.workflow/k10-state.json"'
# 6c K9 error must not swallow a due calendar entry (verifier round 10 D)
P=$T/p7c; mkproj "$P" competition
cfg "$P" '{"overseer_prefix":"x-overseer-","calendar":[{"id":"cz","date":"2026-01-01","roles":["skeptic"]}],"k9":{"N":2,"roles":["skeptic"]},'"$ROLES"'}'
printf 'date\tpkg\tscore\nd\tp\t10\nd\tp\t12\nd\tp\t13\n' > "$P/.workflow/scores.tsv"
run_watch "$P" 2026-10-01 l2
expect cal_despite_k9 '[ $RC = 2 ] && grep -q "日历照常判" <<<"$OUT" && ls "$P"/.workflow/reports/*-skeptic-cz.md >/dev/null 2>&1'
# 6d failure: not in reports/, retried once next run, then given up; state saved
P=$T/p7d; mkproj "$P" competition
cfg "$P" '{"overseer_prefix":"x-overseer-","calendar":[{"id":"cf","date":"2026-01-01","roles":["skeptic"]}],'"$ROLES"'}'
run_watch "$P" 2026-10-01 l3 K10_STUB_FAIL=1
expect fail_first '[ $RC = 1 ] && grep -q "失败第 1 次，下一轮重试" <<<"$OUT" && [ -z "$(ls "$P/.workflow/reports" 2>/dev/null)" ] && ls "$P"/.workflow/k10-failures/*-skeptic-cf.md >/dev/null 2>&1'
run_watch "$P" 2026-10-01 l4 K10_STUB_FAIL=1
expect fail_giveup '[ $RC = 1 ] && grep -q "失败 2 次，放弃" <<<"$OUT"'
run_watch "$P" 2026-10-01 l5
expect fail_no_rerun '[ $RC = 0 ] && grep -q "触发 0 个，待办 0 个" <<<"$OUT"'
# 6e retry succeeds on second run
P=$T/p7e; mkproj "$P" competition
cfg "$P" '{"overseer_prefix":"x-overseer-","calendar":[{"id":"cr","date":"2026-01-01","roles":["skeptic"]}],'"$ROLES"'}'
run_watch "$P" 2026-10-01 l6 K10_STUB_FAIL=1
run_watch "$P" 2026-10-01 l7
expect retry_ok '[ $RC = 0 ] && grep -q "待办 1 个" <<<"$OUT" && ls "$P"/.workflow/reports/*-skeptic-cr.md >/dev/null 2>&1'
# 6f count_above + day2 criteria
P=$T/p7f; mkproj "$P" competition
cfg "$P" '{"overseer_prefix":"x-overseer-","k9":{"N":50,"ext_k":5,"ext_count_above":2,"day2_date":"2026-10-01","day2_cutline_pct":3,"target_rank":1,"roles":["skeptic"]},'"$ROLES"'}'
printf 'rank\tteam\tscore\tsubmissions\tbest_date\n1\ta\t900\t2\tx\n2\tb\t880\t3\tx\n3\tc\t700\t4\tx\n4\td\t690\t4\tx\n5\te\t680\t4\tx\n' > "$P/.workflow/leaderboard.tsv"
printf 'date\tpkg\tscore\nd\tp\t850\n' > "$P/.workflow/scores.tsv"
run_watch "$P" 2026-09-30 l8
expect count_above '[ $RC = 0 ] && grep -rq "有 2 队高于我们" "$P/.workflow/reports/" && ! grep -rq "中位数" "$P/.workflow/reports/"'
run_watch "$P" 2026-10-01 l9
expect day2 '[ $RC = 0 ] && grep -rq "第 2 天对截线" "$P/.workflow/reports/"'
run_watch "$P" 2026-10-02 l10
expect day2_once '[ $RC = 0 ] && grep -q "触发 0 个" <<<"$OUT"'
# 6b malformed scores.tsv -> exit 2 with reason
P=$T/p6b; mkproj "$P" competition
cfg "$P" '{"overseer_prefix":"x-overseer-","k9":{"N":2,"fixed_X":5,"roles":["skeptic"]},'"$ROLES"'}'
printf 'date\tpkg\tscore\nd\tp\tabc\n' > "$P/.workflow/scores.tsv"
run_watch "$P" 2026-10-01 k2
expect bad_tsv '[ $RC = 2 ] && grep -q "判定失败" <<<"$OUT"'
# 6g J: K9 error after position judged must not persist position_fired (verifier round 11)
P=$T/p7g; mkproj "$P" competition
cfg "$P" '{"overseer_prefix":"x-overseer-","k9":{"N":1,"ext_k":5,"target_rank":10,"roles":["skeptic"]},'"$ROLES"'}'
printf 'rank\tteam\tscore\tsubmissions\tbest_date\n1\ta\t900\t2\tx\n2\tb\t880\t3\tx\n' > "$P/.workflow/leaderboard.tsv"
printf 'date\tpkg\tscore\nd\tp\t800\nd\tp\t801\n' > "$P/.workflow/scores.tsv"
run_watch "$P" 2026-10-01 j1
expect J_state_untouched '[ $RC = 2 ] && python3 -c "import json,sys;d=json.load(open(sys.argv[1]));sys.exit(0 if d[\"position_fired\"] is False and d[\"k9_last_judged\"]==0 else 1)" "$P/.workflow/k10-state.json"'
cfg "$P" '{"overseer_prefix":"x-overseer-","k9":{"N":1,"ext_k":5,"target_rank":10,"fixed_X":5,"roles":["skeptic"]},'"$ROLES"'}'
run_watch "$P" 2026-10-01 j2
expect J_fires_after_fix '[ $RC = 0 ] && grep -rq "外部位置" "$P/.workflow/reports/"'
# 6h C crash paths: third party timeout, non-UTF-8 template -> no crash, state saved, retried, not rerun forever
P=$T/p7h; mkproj "$P" competition
cfg "$P" '{"overseer_prefix":"x-overseer-","calendar":[{"id":"ct","date":"2026-01-01","roles":["skeptic"]}],"roles":{"skeptic":{"template":".workflow/templates/skeptic.md","timeout_s":1}}}'
run_watch "$P" 2026-10-01 j3 K10_STUB_SLEEP=3
expect C_timeout '[ $RC = 1 ] && grep -q "启动失败 TimeoutExpired" <<<"$OUT" && grep -q "\"attempts\": 1" "$P/.workflow/k10-state.json"'
P=$T/p7i; mkproj "$P" competition; printf '\xff\xfe\x00bad' > "$P/.workflow/templates/skeptic.md"
cfg "$P" '{"overseer_prefix":"x-overseer-","calendar":[{"id":"cu","date":"2026-01-01","roles":["skeptic"]}],'"$ROLES"'}'
run_watch "$P" 2026-10-01 j4
run_watch "$P" 2026-10-01 j5
run_watch "$P" 2026-10-01 j6
expect C_badtemplate '[ $RC = 0 ] && grep -q "触发 0 个，待办 0 个" <<<"$OUT" && [ -z "$(find "$T/log-j4" "$T/log-j5" "$T/log-j6" -type f)" ]'
# 6j A: the settings.json hook command itself (missing script -> exit 0 + systemMessage; installed -> runs)
TPL=$(cd "$S/../templates" && pwd)/.claude/settings.json
for ev in Stop SubagentStop; do
  c=$(python3 -c "import json,sys;print(json.load(open(sys.argv[1]))['hooks'][sys.argv[2]][0]['hooks'][0]['command'])" "$TPL" "$ev")
  H=$T/home-$ev; mkdir -p "$H"
  OUT=$(echo '{}' | HOME="$H" sh -c "$c" 2>&1); RC=$?
  expect A_missing_$ev '[ $RC = 0 ] && grep -q "systemMessage" <<<"$OUT" && grep -q "未安装" <<<"$OUT"'
  mkdir -p "$H/.claude/scripts"; cp "$S"/k10-*.py "$H/.claude/scripts/"
  OUT=$(echo '{"agent_type":"x"}' | HOME="$H" DUAL_MODEL_ROLE=worker sh -c "$c" 2>&1); RC=$?
  expect A_installed_$ev '[ $RC = 0 ] && ! grep -q "未安装" <<<"$OUT"'
  # Windows (2026-09-29 MSI): Git Bash finds a Store stub named python3 that only prints "Python was not found".
  # The hook must probe that the interpreter really runs and fall back to python, not fail open silently.
  B=$T/bin-$ev; mkdir -p "$B"; REALPY=$(command -v python3)
  printf '#!/bin/sh\necho "Python was not found"\nexit 9009\n' > "$B/python3"; ln -sf "$REALPY" "$B/python"; chmod +x "$B/python3"
  E=$T/empty-$ev; mkdir -p "$E"
  OUT=$(echo '{"agent_type":"x","stop_hook_active":false}' | HOME="$H" DUAL_MODEL_ROLE=overseer CLAUDE_PROJECT_DIR="$E" PATH="$B:$PATH" sh -c "$c" 2>&1); RC=$?
  expect A_stub_python3_falls_back_$ev '[ $RC = 0 ] && ! grep -q "Python was not found" <<<"$OUT" && grep -q "k10-" <<<"$OUT"'
  rm -f "$B/python"; printf '#!/bin/sh\nexit 9009\n' > "$B/python"; chmod +x "$B/python"
  OUT=$(echo '{}' | HOME="$H" PATH="$B:$PATH" sh -c "$c" 2>&1); RC=$?
  expect A_no_python_says_so_$ev '[ $RC = 0 ] && grep -q "systemMessage" <<<"$OUT" && grep -q "Python" <<<"$OUT" && ! grep -q "未安装" <<<"$OUT"'
done
# 7 proposer isolation: cwd outside project, project path not in prompt
P=$T/p8; mkproj "$P" competition
cfg "$P" '{"overseer_prefix":"x-overseer-","calendar":[{"id":"c9","date":"2026-01-01","roles":["proposer"]}],'"$ROLES"'}'
run_watch "$P" 2026-10-01 m
expect iso_cwd '! grep -q "CWD: $P" "$T/log-m/call-0.txt" && grep -q "PROPOSER TEMPLATE" "$T/log-m/call-0.txt" && ! grep -q "$P" "$T/log-m/call-0.txt"'
# ---------------- stop gate
G() { OUT=$(cd "$1" && echo "{\"stop_hook_active\": ${3:-false}}" | env DUAL_MODEL_ROLE="$2" CLAUDE_PROJECT_DIR="$1" python3 "$S/k10-stop-gate.py" 2>&1); }
P=$T/g1; mkdir -p "$P/.workflow/reports" "$P/.workflow/responses"
G "$P" overseer; expect gate_empty '! grep -q block <<<"$OUT" && grep -q "查了 0 份报告" <<<"$OUT"'
printf 'S1 a\nS2 b\nS10 c\n' > "$P/.workflow/reports/r1.md"
G "$P" worker;   expect gate_worker '! grep -q block <<<"$OUT"'
G "$P" overseer; expect gate_noresp 'grep -q "\"decision\": \"block\"" <<<"$OUT" && grep -q "无回应文件" <<<"$OUT"'
printf 'S1 接受 理由\nS2 驳回 理由\nS1 提到 S10 但没表态\n' > "$P/.workflow/responses/r1.md"
G "$P" overseer; expect gate_partial 'grep -q "缺 S10" <<<"$OUT" && ! grep -q "缺 S1[,）]" <<<"$OUT"'
printf 'S10 部分接受\n' >> "$P/.workflow/responses/r1.md"
G "$P" overseer; expect gate_done '! grep -q block <<<"$OUT" && [ ! -f "$P/.workflow/k10-gate.json" ]'
printf 'S3 x\n' > "$P/.workflow/reports/r2.md"
G "$P" overseer false; G "$P" overseer true; G "$P" overseer true
expect gate_3rd 'grep -q "第 3/3 次" <<<"$OUT"'
G "$P" overseer true; expect gate_release '! grep -q "\"decision\"" <<<"$OUT" && grep -q "systemMessage" <<<"$OUT" && grep -q "这次放行" <<<"$OUT"'
G "$P" overseer false; expect gate_newturn_resets 'grep -q "本回合第 1/3 次" <<<"$OUT"'
# Windows locale (2026-09-29 MSI): stdout defaulted to GBK, CC can't parse the JSON and silently lets the turn end.
# PYTHONIOENCODING=gbk reproduces that locale here; the block JSON must still be UTF-8.
BYTES=$T/gate-gbk.out
(cd "$P" && echo '{"stop_hook_active": false}' | env PYTHONIOENCODING=gbk DUAL_MODEL_ROLE=overseer CLAUDE_PROJECT_DIR="$P" python3 "$S/k10-stop-gate.py" > "$BYTES" 2>/dev/null)
expect gate_stdout_utf8_under_gbk 'python3 -c "import json,sys;d=json.loads(open(sys.argv[1],\"rb\").read().decode(\"utf-8\"));sys.exit(0 if d[\"decision\"]==\"block\" and \"回应\" in d[\"reason\"] else 1)" "$BYTES"'
OUT=$(cd "$P" && env -u DUAL_MODEL_ROLE CLAUDE_PROJECT_DIR="$P" python3 "$S/k10-stop-gate.py" --check < /dev/null 2>&1)
expect gate_check_readonly 'grep -q "r2.md 缺 (无回应文件)" <<<"$OUT" && ! grep -q decision <<<"$OUT" && grep -q "\"count\": 1" "$P/.workflow/k10-gate.json"'
# ---------------- subagent report
R() { OUT=$(echo "$2" | env CLAUDE_PROJECT_DIR="$1" python3 "$S/k10-subagent-report.py" 2>&1); }
P=$T/r1; mkdir -p "$P"
R "$P" '{"agent_type":"critic","agent_id":"a1","last_assistant_message":"x"}'
expect rep_skip_critic '[ ! -d "$P/.workflow/reports" ] && grep -q "跳过" <<<"$OUT"'
R "$P" '{"agent_type":"skeptic","agent_id":"a2","last_assistant_message":"S1 原文"}'
R "$P" '{"agent_type":"skeptic","agent_id":"a3","last_assistant_message":"S1 第二份"}'
expect rep_two 'ls "$P"/.workflow/reports/*-skeptic-a2.md "$P"/.workflow/reports/*-skeptic-a3.md >/dev/null && grep -q "S1 原文" "$P"/.workflow/reports/*-a2.md'
R "$P" '{"agent_type":"verifier","agent_id":"a4","agent_transcript_path":"/t.jsonl"}'
expect rep_nomsg 'grep -q "没有 last_assistant_message" "$P"/.workflow/reports/*-a4.md'
# Windows locale: CC sends UTF-8 on stdin; under a GBK default the report text would be mangled.
echo '{"agent_type":"skeptic","agent_id":"a5","last_assistant_message":"S1 中文原文"}' | env PYTHONIOENCODING=gbk CLAUDE_PROJECT_DIR="$P" python3 "$S/k10-subagent-report.py" >/dev/null 2>&1
expect rep_stdin_utf8_under_gbk 'grep -q "S1 中文原文" "$P"/.workflow/reports/*-a5.md'
if [ "$fail" -eq 0 ]; then echo "checked $n cases: all passed"; exit 0; fi
echo "checked $n cases: $fail failed"; exit 1
