#!/usr/bin/env bash
# Regression test for scripts/dual-model-mode.sh (the rules) and for any bash
# launcher that calls it (the wiring). Stub `claude` prints its argv.
# Usage: bash test_dual_model_mode.sh [launcher.sh]
#   default launcher = ../../linux/dual-model.sh. For ~/.bashrc, extract its cc/cc-alt
#   functions into a file first (~/.bashrc returns early when not interactive).
# Output: "checked N cases: all passed" or the failures; exit 1 on any failure.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPTS=$(cd "$HERE/.." && pwd)
MODE="$SCRIPTS/dual-model-mode.sh"
LAUNCHER="${1:-$(cd "$HERE/../../linux" && pwd)/dual-model.sh}"
[ -x "$MODE" ] || { echo "not executable: $MODE" >&2; exit 2; }
[ -f "$LAUNCHER" ] || { echo "launcher not found: $LAUNCHER" >&2; exit 2; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"
printf '#!/bin/sh\nprintf "CLAUDE-ARGS:"; for a in "$@"; do printf " [%%s]" "$a"; done; echo " ROLE=$DUAL_MODEL_ROLE"\n' > "$T/bin/claude"
chmod +x "$T/bin/claude"
n=0; fail=0
check() { # name rc_want rc_got out regex
  n=$((n+1))
  local ok=1
  if [ "$5" = EMPTY ]; then [ -z "$4" ] || ok=0; else printf '%s' "$4" | grep -qE -- "$5" || ok=0; fi
  if [ "$3" = "$2" ] && [ "$ok" = 1 ]; then :; else
    fail=$((fail+1)); echo "FAIL $1: rc=$3 want=$2 re=$5"; printf '%s\n' "$4" | tail -5 | sed 's/^/    /'; fi
}
# ---- rules: dual-model-mode.sh mode
m() { # name content rc_want regex
  local f="$T/ctx-$1.md"; printf '%b' "$2" > "$f"
  local out rc; out=$("$MODE" mode "$f" 2>&1); rc=$?
  check "mode/$1" "$3" "$rc" "$out" "$4"
}
m none        "# ctx\n"                                0 EMPTY
m project     "a\nworkflow-mode: project\n"            0 '^project$'
m comp        "workflow-mode: competition\n"           0 '^competition$'
m crlf        "workflow-mode: competition\r\n"         0 '^competition$'
m trailing    "workflow-mode:   research  \n"          0 '^research$'
m bad_value   "workflow-mode: 比赛\n"                   1 'allowed: project'
m bad_case    "workflow-mode: Competition\n"           1 'allowed: project'
m empty_value "workflow-mode:\n"                       1 'allowed: project'
m multi       "workflow-mode: project\nworkflow-mode: project\n" 1 '2 .workflow-mode:. lines'
m near_indent "  workflow-mode: competition\n"         1 'looks like a mode line'
m near_under  "workflow_mode: competition\n"           1 'looks like a mode line'
m near_fw     "workflow-mode： competition\n"           1 'looks like a mode line'
m near_upper  "Workflow-Mode: competition\n"           1 'looks like a mode line'
m template    "<!-- 行首顶格写 workflow-mode，后跟英文冒号 -->\n_未选模式。_\n" 0 EMPTY
out=$("$MODE" mode "$T/does-not-exist.md" 2>&1); check mode/no_file 0 $? "$out" EMPTY
# ---- rules: dual-model-mode.sh effort (warn-only, always exit 0)
e() { # name regex env...
  local name=$1 re=$2; shift 2
  local out rc; out=$(env -u CLAUDE_CODE_EFFORT_LEVEL -u DUAL_MODEL_EFFORT "$@" "$MODE" effort 2>&1); rc=$?
  check "effort/$name" 0 "$rc" "$out" "$re"
}
e default   '^high$'
e dm_xhigh  '^xhigh$'                          DUAL_MODEL_EFFORT=xhigh
e dm_low    'WARNING: DUAL_MODEL_EFFORT=.medium.*using high'  DUAL_MODEL_EFFORT=medium
e dm_upper  'WARNING: DUAL_MODEL_EFFORT=.HIGH'  DUAL_MODEL_EFFORT=HIGH
e env_low   'WARNING: CLAUDE_CODE_EFFORT_LEVEL=.medium. outranks' CLAUDE_CODE_EFFORT_LEVEL=medium
e env_bad   'WARNING: CLAUDE_CODE_EFFORT_LEVEL=.HIGH. is not'     CLAUDE_CODE_EFFORT_LEVEL=HIGH
e env_max   '^high$'                           CLAUDE_CODE_EFFORT_LEVEL=max
# ---- wiring: the launcher
l() { # name role content rc_want regex [env...]
  local name=$1 role=$2 content=$3 rc_want=$4 re=$5; shift 5
  local d="$T/p-$name" out rc
  mkdir -p "$d"; touch "$d/WORKFLOW.md"; [ "$content" != NONE ] && printf '%b' "$content" > "$d/context.md"
  out=$(cd "$d" && printf '%s\n\n' "$role" | env -u CLAUDE_CODE_EFFORT_LEVEL -u DUAL_MODEL_EFFORT \
        PATH="$T/bin:$PATH" DUAL_MODEL_SCRIPTS="$SCRIPTS" "$@" \
        bash -c ". \"$LAUNCHER\" >/dev/null 2>&1; cc; echo RC=\$?" 2>&1)
  rc=$(printf '%s\n' "$out" | sed -n 's/^RC=//p' | tail -1)
  check "launcher/$name" "$rc_want" "$rc" "$out" "$re"
}
NOEFF='^CLAUDE-ARGS:([^-]|-[^-]|--[^e])* ROLE='
l nomode     1 "# ctx\n"                     0 'no workflow mode yet'
l nomode_eff 1 "# ctx\n"                     0 "$NOEFF"
l project    1 "workflow-mode: project\n"    0 "$NOEFF"
l comp       1 "workflow-mode: competition\n" 0 '\[--effort\] \[high\] ROLE=overseer'
l comp_envlo 1 "workflow-mode: competition\n" 0 '\[--effort\] \[high\] ROLE=overseer' CLAUDE_CODE_EFFORT_LEVEL=medium
l comp_warn  1 "workflow-mode: competition\n" 0 'WARNING: CLAUDE_CODE_EFFORT_LEVEL' CLAUDE_CODE_EFFORT_LEVEL=medium
l worker     2 "workflow-mode: competition\n" 0 'Workflow mode: competition \(knob.*ROLE=worker'
l worker_noe 2 "workflow-mode: competition\n" 0 "$NOEFF"
l worker_nom 2 "# ctx\n"                      0 'and execute\.\] ROLE=worker'
l bad        1 "workflow-mode: 比赛\n"         1 'Not launching'
l near       1 "workflow_mode: competition\n" 1 'looks like a mode line'
l norole     x "workflow-mode: competition\n" 0 '^CLAUDE-ARGS: ROLE=$'
l noscript_nomode 1 "# ctx\n"                 0 'not found; workflow mode NOT checked' DUAL_MODEL_SCRIPTS=/nonexistent
l noscript_mode   1 "workflow-mode: project\n" 1 'is missing.*Not launching' DUAL_MODEL_SCRIPTS=/nonexistent
if [ "$fail" -eq 0 ]; then echo "checked $n cases: all passed (launcher: $LAUNCHER)"; exit 0; fi
echo "checked $n cases: $fail failed"; exit 1
