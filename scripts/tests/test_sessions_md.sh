#!/usr/bin/env bash
# Regression test for scripts/sessions-md.py (sessions.md registry), on a fake HOME — never touches the real ~/.claude.
# Usage: bash test_sessions_md.sh
# Output: "checked N cases: all passed" or the failures; exit 1 on any failure.
set -u
umask 022
HERE=$(cd "$(dirname "$0")" && pwd)
PY="$HERE/../sessions-md.py"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
P="$T/proj"; mkdir -p "$P" "$HOME/.claude"
P=$(cd "$P" && pwd -P)
SLUG=$(printf '%s' "$P" | sed 's/[^A-Za-z0-9]/-/g')
TR="$HOME/.claude/projects/$SLUG"; TEL="$HOME/.claude/manager/telemetry"
mkdir -p "$TR"
echo vps > "$HOME/.claude/machine-tag"
n=0; fail=0
unset CLAUDE_CODE_SESSION_ID  # 本测试可能在一个 CC 会话里跑；各用例自己设
run() { out=$(cd "$P" && python3 "$PY" . "$@" 2>&1); rc=$?; }
chk() { # name rc_want regex [file-regex]
  n=$((n+1))
  if [ "$rc" = "$2" ] && printf '%s' "$out" | grep -qE -- "$3" \
     && { [ -z "${4:-}" ] || grep -qE -- "$4" "$P/sessions.md"; }; then :; else
    fail=$((fail+1)); echo "FAIL $1: rc=$rc want=$2 re=$3 ${4:+file-re=$4}"; printf '%s\n' "$out" | tail -4 | sed 's/^/    /'; fi
}
transcript() { # sid name model effort t0 t1 [entrypoint]
  local ep="${7:-cli}"
  {
    printf '{"type":"custom-title","customTitle":"%s","sessionId":"%s"}\n' "$2" "$1"
    printf '{"type":"user","message":{"role":"user","content":"hi"},"timestamp":"%s","sessionId":"%s","entrypoint":"%s"}\n' "$5" "$1" "$ep"
    printf '{"type":"assistant","message":{"model":"%s"},"effort":"%s","timestamp":"%s","sessionId":"%s","entrypoint":"%s"}\n' "$3" "$4" "$6" "$1" "$ep"
  } > "$TR/$1.jsonl"
}
A=aaaaaaaa-0000-0000-0000-000000000001
B=bbbbbbbb-0000-0000-0000-000000000002
C=cccccccc-0000-0000-0000-000000000003
transcript $A vps-proj-overseer-x claude-opus-5-5 high 2026-10-01T10:00:00.000Z 2026-10-01T12:00:00.000Z
transcript $B vps-proj-worker-y claude-sonnet-5-5 medium 2026-10-01T10:30:00.000Z 2026-10-01T11:00:00.000Z

# 1. 没有遥测：只靠 transcript，SessionEnd 写「未知」
run; chk no_telemetry 0 '遥测 不存在（未装 manager）.*新增 2' '\| 全局者 \| vps-proj-overseer-x \| claude-opus-5-5 \| high \| 未知 \| ✓ \|'
# 2. 备注只写自己那一行（sessionId 取环境变量）
out=$(cd "$P" && CLAUDE_CODE_SESSION_ID=$A python3 "$PY" . --note 'task1 完成 | 含竖线'); rc=$?
chk note_env 0 "备注写入 aaaaaaaa" 'task1 完成 \\\| 含竖线 \|$'
# 3. 再跑一次：备注保留，按来源更新 2
run; chk note_kept 0 '新增 0，按来源更新 2' 'task1 完成 \\\| 含竖线 \|$'
# 4. 加遥测：project_dir 等于项目的行算，cwd 等于项目但 project_dir 在别处的不算；SessionEnd 取自 events
mkdir -p "$TEL"
printf '{"session_id":"%s","session_name":"vps-proj-overseer-x","model":{"id":"claude-opus-5-5"},"effort":{"level":"high"},"cwd":"%s","workspace":{"project_dir":"%s"},"_captured_at":"2026-10-01T12:05:00Z"}\n' $A "$P" "$P" > "$TEL/status-events.ndjson"
printf '{"session_id":"%s","session_name":"路过","cwd":"%s","workspace":{"project_dir":"/root"},"_captured_at":"2026-10-01T12:06:00Z"}\n' $C "$P" >> "$TEL/status-events.ndjson"
{ printf '{"session_id":"x","hook_event_name":"Stop","_captured_at":"2026-10-01T09:00:00Z"}\n'
  printf '{"session_id":"%s","hook_event_name":"SessionEnd","reason":"other","_captured_at":"2026-10-01T12:10:00Z"}\n' $A; } > "$TEL/events.ndjson"
run; chk telemetry 0 'status 1 份 2 行.*events 1 份 2 行（自 2026-10-01T09:00）.*本项目会话 2 行' '2026-10-01 12:10 \| vps \| 全局者 .* \| ✓ \| ✓ \|'
n=$((n+1)); grep -q "$C" "$P/sessions.md" && { fail=$((fail+1)); echo "FAIL cwd_only: 路过的会话被算进来了"; }
# 5. 工作者没有 SessionEnd、开始时刻在 events 覆盖范围内：写「无」（可能崩了 / 被 kill / 还在跑）
n=$((n+1)); grep -qE 'vps-proj-worker-y .* \| 无 \| ✓ \|' "$P/sessions.md" || { fail=$((fail+1)); echo "FAIL no_end: 工作者行不是「无」"; }
# 6. transcript 删了、遥测也没它：整行保留，备注不丢
rm "$TR/$B.jsonl"
out=$(cd "$P" && python3 "$PY" . --note '工作者补记' --sid $B 2>&1); rc=$?
chk kept_row 0 '原样保留 1；备注写入 bbbbbbbb' 'vps-proj-worker-y .*工作者补记 \|$'
# 7. --note 的会话哪里都没有：拒绝
run --note x --sid dddddddd-0000-0000-0000-000000000004; chk note_unknown 1 '都找不到，没写'
# 8. 同角色时间重叠超过阈值才标
transcript $C vps-proj-overseer-z claude-opus-5-5 high 2026-10-01T11:00:00.000Z 2026-10-01T13:00:00.000Z
run; chk overlap 0 '新增 1' '\| cccccccc-0000-0000-0000-000000000003 \|'
n=$((n+1)); grep -qE '\| ✓ \| ✓ \| cccccccc \| aaaaaaaa' "$P/sessions.md" || { fail=$((fail+1)); echo "FAIL overlap_mark"; }
# 9. -p 会话：角色「-p」，名字用首条提示；events 覆盖到它的开始时刻但没有 SessionEnd → 「无」
transcript eeeeeeee-0000-0000-0000-000000000005 "" claude-opus-5-5 high 2026-10-02T10:00:00.000Z 2026-10-02T10:05:00.000Z sdk-cli
sed -i '1d' "$TR/eeeeeeee-0000-0000-0000-000000000005.jsonl"
run; chk dash_p 0 '新增 1' '\| -p \| （无名，-p）hi \|'
n=$((n+1)); grep -qE '（无名，-p）hi \| claude-opus-5-5 \| high \| 无 \|' "$P/sessions.md" || { fail=$((fail+1)); echo "FAIL dash_p_no_end"; }
# 9b. -p 会话没有 statusline、只在 transcript 里，但 events 里有它的 SessionEnd：要认出来
printf '{"session_id":"eeeeeeee-0000-0000-0000-000000000005","hook_event_name":"SessionEnd","reason":"other","_captured_at":"2026-10-02T10:06:00Z"}\n' >> "$TEL/events.ndjson"
run; chk dash_p_end 0 '新增 0' '（无名，-p）hi \| claude-opus-5-5 \| high \| ✓ \|'
# 10. 文件被手改坏（格数不对）：拒绝覆盖
cp "$P/sessions.md" "$T/good.md"; sed -i '0,/^| 20/s/^| 20/| x | 20/' "$P/sessions.md"
run; chk corrupt 1 '解析不了，拒绝覆盖'
n=$((n+1)); cmp -s <(sed '0,/^| 20/s/^| x | 20/| 20/' "$P/sessions.md") "$T/good.md" || { fail=$((fail+1)); echo "FAIL corrupt_untouched"; }
cp "$T/good.md" "$P/sessions.md"
# 11. 锁：别的进程持锁 2 秒，本次等到它放手再写；持锁进程被 SIGKILL 后锁随之释放，不留残锁
LOCK="$P/sessions-md-$(printf '%s' "$SLUG" | tail -c 60).lock"
hold() { python3 -c 'import fcntl,sys,time; f=open(sys.argv[1],"a+"); fcntl.flock(f,fcntl.LOCK_EX); open(sys.argv[1]+".held","w"); time.sleep(float(sys.argv[2]))' "$LOCK" "$1" & HP=$!; while [ ! -e "$LOCK.held" ]; do sleep 0.05; done; rm -f "$LOCK.held"; }
hold 2; t0=$(date +%s); run; wait; t1=$(date +%s)
chk lock_wait 0 '新增 0'
n=$((n+1)); [ $((t1 - t0)) -ge 1 ] || { fail=$((fail+1)); echo "FAIL lock_wait_blocked: 没等锁就写了（$((t1 - t0)) 秒）"; }
hold 60; kill -9 $HP; wait $HP 2>/dev/null; run; chk lock_after_kill 0 '新增 0'
# 12. 两个角色同时收尾：两条备注都在
( cd "$P" && python3 "$PY" . --note '并发A' --sid $A >/dev/null 2>&1; echo $? > "$T/rcA" ) &
( cd "$P" && python3 "$PY" . --note '并发C' --sid $C >/dev/null 2>&1; echo $? > "$T/rcC" ) & wait
n=$((n+1)); [ "$(cat "$T/rcA")$(cat "$T/rcC")" = 00 ] && grep -q '并发A' "$P/sessions.md" && grep -q '并发C' "$P/sessions.md" \
  || { fail=$((fail+1)); echo "FAIL concurrent: rc=$(cat "$T/rcA")/$(cat "$T/rcC") 或丢了一条备注"; }
n=$((n+1)); ls "$P"/.sessions-md-*.tmp >/dev/null 2>&1 && { fail=$((fail+1)); echo "FAIL tmp_left: 留下了临时文件"; }
# 12b. 自己是 A 时写 B：不带 --backfill 拒绝；B 已有备注时带了也拒绝；空备注行带 --backfill 才写，带前缀
out=$(cd "$P" && CLAUDE_CODE_SESSION_ID=$A python3 "$PY" . --note x --sid $C 2>&1); rc=$?; chk not_self 1 '不是自己'
out=$(cd "$P" && CLAUDE_CODE_SESSION_ID=$A python3 "$PY" . --note x --sid $B --backfill 2>&1); rc=$?; chk backfill_nonempty 1 '只写备注为空的行'
out=$(cd "$P" && CLAUDE_CODE_SESSION_ID=$A python3 "$PY" . --note '崩前做完 task9' --sid eeeeeeee-0000-0000-0000-000000000005 --backfill 2>&1); rc=$?
chk backfill 0 '备注写入 eeeeeeee' '补记（aaaaaaaa）：崩前做完 task9 \|$'
# 12c. 自检：运行脚本的会话不在来源里 → 拒绝；--dry-run 不做自检
out=$(cd "$P" && CLAUDE_CODE_SESSION_ID=ffffffff-0000-0000-0000-000000000006 python3 "$PY" . 2>&1); rc=$?; chk selfcheck 1 '自检：运行本脚本的会话 ffffffff'
out=$(cd "$P" && CLAUDE_CODE_SESSION_ID=ffffffff-0000-0000-0000-000000000006 python3 "$PY" . --dry-run 2>&1); rc=$?; chk selfcheck_dry 0 '为空的角色会话 [0-9]+ 行'
# 12d. 文件里没有每次都变的行（两机各跑一次不该冲突）：连跑两次内容逐字相同
cp "$P/sessions.md" "$T/a.md"; run; n=$((n+1)); cmp -s "$P/sessions.md" "$T/a.md" || { fail=$((fail+1)); echo "FAIL stable: 两次运行内容不同"; }
# 12e. 含竖线、以反斜杠结尾的格：来源已查不到、整行保留时，连跑三次逐字相同、内容不丢
transcript 99999999-0000-0000-0000-000000000009 "" claude-opus-5-5 high 2026-10-03T10:00:00.000Z 2026-10-03T10:05:00.000Z sdk-cli
sed -i '1d; s/"content":"hi"/"content":"a|b 模板 c:\\\\x"/' "$TR/99999999-0000-0000-0000-000000000009.jsonl"
run; chk pipe_new 0 '新增 1' '（无名，-p）a\\\|b 模板 c:\\x \|'
out=$(cd "$P" && python3 "$PY" . --sid 99999999-0000-0000-0000-000000000009 --note 'x|y \' 2>&1); rc=$?
chk no_env_warn 0 '警告：没有环境变量 CLAUDE_CODE_SESSION_ID'
rm "$TR/99999999-0000-0000-0000-000000000009.jsonl"; run; cp "$P/sessions.md" "$T/p1.md"; run; run
n=$((n+1)); cmp -s "$P/sessions.md" "$T/p1.md" || { fail=$((fail+1)); echo "FAIL pipe_stable: 三次运行内容不同"; diff "$T/p1.md" "$P/sessions.md" | head -4; }
n=$((n+1)); grep -qF '| （无名，-p）a\|b 模板 c:\x |' "$P/sessions.md" && grep -qF '| x\|y \  |' "$P/sessions.md" \
  || { fail=$((fail+1)); echo "FAIL pipe_content: 竖线或反斜杠被改了"; grep 99999999 "$P/sessions.md"; }
# 12f. 只有标题行、没有一行带时间戳的 transcript：不算会话，也不让重叠计算崩
printf '{"type":"custom-title","customTitle":"vps-proj-worker-ghost","sessionId":"77777777-0000-0000-0000-000000000007"}\n' > "$TR/77777777-0000-0000-0000-000000000007.jsonl"
run; chk ghost 0 '读出会话 [0-9]+ 个'
n=$((n+1)); grep -q ghost "$P/sessions.md" && { fail=$((fail+1)); echo "FAIL ghost_row"; }
# 12f2. 文件权限按 umask（不是 mkstemp 的 0600）
n=$((n+1)); m=$(stat -c %a "$P/sessions.md"); [ "$m" = 644 ] || { fail=$((fail+1)); echo "FAIL mode: sessions.md 权限是 $m，期望 644（umask 022）"; }
# 12g. 摘要列出最近的空备注会话（造一个已结束、没写备注的工作者）
transcript 66666666-0000-0000-0000-000000000006 vps-proj-worker-quiet claude-sonnet-5-5 high 2026-10-04T10:00:00.000Z 2026-10-04T11:00:00.000Z
printf '{"session_id":"66666666-0000-0000-0000-000000000006","hook_event_name":"SessionEnd","_captured_at":"2026-10-04T11:01:00Z"}\n' >> "$TEL/events.ndjson"
run; chk empty_list 0 '为空的角色会话 1 行（最近的：66666666 vps-proj-worker-quiet；'
# 12h. /as-overseer 第 2 步取 N 的那条命令原样跑一遍（措辞契约）
out=$(cd "$P" && out2=$(python3 "$PY" . --dry-run 2>&1 >/dev/null); echo "sessions-md rc=$?"; printf '%s\n' "$out2" | grep -o '为空的角色会话 [0-9]* 行' || printf '%s\n' "$out2" | tail -2); rc=0
chk overseer_grep 0 '^为空的角色会话 1 行$'
n=$((n+1)); printf '%s\n' "$out" | grep -qx 'sessions-md rc=0' || { fail=$((fail+1)); echo "FAIL overseer_grep_rc: $out"; }
# 13. 范围算不出：空项目目录（transcript 目录在但是空的、没有遥测、没有文件）→ 退出 1，--dry-run 也一样
P2="$T/empty"; mkdir -p "$P2"; P2=$(cd "$P2" && pwd -P); mkdir -p "$HOME/.claude/projects/$(printf '%s' "$P2" | sed 's/[^A-Za-z0-9]/-/g')"; rm -rf "$TEL"
out=$(cd "$P2" && python3 "$PY" . 2>&1); rc=$?; chk nothing 1 '本项目 0 个会话.*读出会话 0 个.*范围算不出'
out=$(cd "$P2" && python3 "$PY" . --dry-run 2>&1); rc=$?; chk nothing_dry 1 '范围算不出'
n=$((n+1)); [ -e "$P2/sessions.md" ] && { fail=$((fail+1)); echo "FAIL nothing_wrote"; }
# 13b. 有遥测但没有本项目的行：摘要明写 0 行
mkdir -p "$TEL"; printf '{"session_id":"z","workspace":{"project_dir":"/elsewhere"},"_captured_at":"2026-10-01T00:00:00Z"}\n' > "$TEL/status-events.ndjson"; : > "$TEL/events.ndjson"
out=$(cd "$P2" && python3 "$PY" . --dry-run 2>&1); rc=$?; chk tele_zero 1 '含本项目路径的行 0 行.*events 1 份 0 行（0 行）'

if [ "$fail" = 0 ]; then echo "checked $n cases: all passed"; else echo "checked $n cases: $fail failed"; exit 1; fi
