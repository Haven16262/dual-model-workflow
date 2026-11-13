#!/usr/bin/env bash
# Regression test for scripts/security-scan.sh (pre-review keyword scan; exit 0 clean / 1 hit / 2 did not run).
# Usage: bash test_security_scan.sh
# Output: "checked N cases: all passed" or the failures; exit 1 on any failure.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SCAN="$HERE/../security-scan.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1  # 不吃本机的全局钩子与配置
g() { git -C "$T/r" -c user.name=t -c user.email=t@t "$@" >/dev/null 2>&1; }
n=0; fail=0
c() { # name rc_want regex [args...]
  n=$((n+1))
  local name=$1 want=$2 re=$3; shift 3
  local out rc; out=$(cd "$T/r" && bash "$SCAN" "$@" 2>&1); rc=$?
  if [ "$rc" = "$want" ] && printf '%s' "$out" | grep -qE -- "$re"; then :; else
    fail=$((fail+1)); echo "FAIL $name: rc=$rc want=$want re=$re"; printf '%s\n' "$out" | tail -3 | sed 's/^/    /'; fi
}
mkdir -p "$T/r"
c not_git    2 '不是 git 仓库'
g init -q
n=$((n+1)); out=$(cd "$T/r/.git" && bash "$SCAN" 2>&1); rc=$?
[ "$rc" = 2 ] && printf '%s' "$out" | grep -q '不在 git 工作树里' || { fail=$((fail+1)); echo "FAIL in_dotgit: rc=$rc $out"; }
c no_commit  2 'HEAD 不存在'
echo 'x = 1' > "$T/r/a.py"; g add a.py; g commit -qm base
base=$(git -C "$T/r" rev-parse HEAD)
c clean      0 '未命中'
c two_args   2 '只收 1 个参数' "$base" extra
c bad_ref    2 '不是一个 commit' nosuchref
c tree_ref   2 '不是一个 commit' "$base^{tree}"
c dash_ref   2 '不是一个 commit' --output=x
c empty_ref  2 '不是一个 commit' ''
c base_clean 0 '未命中' "$base"
echo 'TOKEN = 1' > "$T/r/new.py"
c untracked  1 'new\.py:1:'
rm "$T/r/new.py"; echo 'import subprocess' >> "$T/r/a.py"
c unstaged   1 'a\.py:2: subprocess'
g commit -qam second
c committed_no_base 0 '未命中'
c committed_base    1 'a\.py:2: subprocess' "$base"
c scope_base 1 "范围：仓库根；未提交改动 \\+ 未跟踪文件 \\+ $base\\.\\.HEAD" "$base"
mkdir -p "$T/r/sub"; echo 'x' > "$T/r/sub/y.py"; g add sub/y.py; g commit -qm sub
n=$((n+1)); out=$(cd "$T/r/sub" && bash "$SCAN" 2>&1); rc=$?
[ "$rc" = 0 ] && printf '%s' "$out" | grep -q '范围：子树 sub/；' || { fail=$((fail+1)); echo "FAIL scope_sub: rc=$rc $out"; }
echo 'password: x' > "$T/r/notes.md"
c md_excluded 0 '未命中'
if [ "$fail" -eq 0 ]; then echo "checked $n cases: all passed"; exit 0; fi
echo "checked $n cases: $fail failed"; exit 1
