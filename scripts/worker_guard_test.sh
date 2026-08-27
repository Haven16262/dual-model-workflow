#!/usr/bin/env bash
# worker_guard.py 的分类回归测试。装完守卫后跑一次；改过拦截集合后必须再跑。
#   用法: bash scripts/worker_guard_test.sh [python 解释器，默认 python3]
#
# 为什么值得有：拦截判断从「子串匹配」改成「按命令位置解析」，正是因为子串
# 匹配把 `git log --grep push` 误判成 push——而硬拒路径没有逃生舱，误伤会把
# 工作者永久卡死在一条无害命令上。heredoc 正文同理（文档里写 push 当例子）。
set -u
PY="${1:-python3}"
GUARD="$HOME/.claude/scripts/worker_guard.py"
[ -f "$GUARD" ] || { echo "找不到 $GUARD —— 先按 README 安装"; exit 1; }

export CLAUDE_PROJECT_DIR="${TMPDIR:-/tmp}/worker-guard-selftest"
mkdir -p "$CLAUDE_PROJECT_DIR"
pass=0; fail=0

# 输入输出两端都显式走 UTF-8 字节，绝不依赖解释器的 locale。
#
# 这不是洁癖。原来两端都用 `print` / `sys.stdin.read()`，在简中 Windows 上是
# python(cp936) 管到 python(cp936)：自洽地错着，22 条分类用例全过，却掩盖了
# 「Claude Code 按 UTF-8 读钩子 stdout、解析失败、守卫静默失败放行」这个真
# 故障。自测用同一个解释器读自己的输出，天然测不出编码问题。
mkjson() {
  "$PY" -c "
import json, sys
sys.stdout.buffer.write(json.dumps(
    {'tool_name': 'Bash', 'tool_input': {'command': sys.argv[1]}}).encode('utf-8'))" "$1"
}

cls() {
  mkjson "$1" | "$PY" -S "$GUARD" | "$PY" -c "
import sys, json
raw = sys.stdin.buffer.read()
if not raw:
    print('pass-through'); raise SystemExit
try:
    d = raw.decode('utf-8')            # 严格解码：模拟 Claude Code 的读法
except UnicodeDecodeError as e:
    print('NOT-UTF8: %s' % e); raise SystemExit
r = json.loads(d)['hookSpecificOutput']['permissionDecisionReason']
print('hard-deny' if '没有放行通道' in r else 'queued')"
}

t() {
  local got; got=$(cls "$2")
  if [ "$got" = "$1" ]; then pass=$((pass+1))
  else fail=$((fail+1)); printf '  ✗ want=%-12s got=%-12s %s\n' "$1" "$got" "$(printf '%s' "$2" | head -1)"; fi
}

# 放行：不该被拦的
t pass-through "npm test"
t pass-through "git status"
t pass-through "git log --grep push"
t pass-through "echo git push"
t pass-through "git config push.default simple"
t pass-through "ssh-keygen -l -f key"
t pass-through "grep -r ssh /etc"
t pass-through "cat chmod.log"
# 硬拒：真的 push，含各种写法
t hard-deny "git push"
t hard-deny "git push origin main"
t hard-deny "git -C /srv/app push"
t hard-deny "cd /srv && git push --force"
t hard-deny "FOO=1 git push"
t hard-deny "$(printf 'cd /srv\ngit push origin main')"
# 拒 + 入队
t queued "ssh havenn1 uptime"
t queued "chmod +x deploy.sh"
t queued "cat x | ssh h1 tee y"
t queued "/usr/bin/ssh h1 ls"
# heredoc 正文是数据，不是命令
t pass-through "$(printf 'cat > doc.md <<EOF\ngit push origin main\nEOF')"
t pass-through "$(printf 'cat > n.md <<EOF\nssh havenn1 是个例子\nEOF')"
t pass-through "$(printf "cat > a.md <<'MD'\nchmod 777 /x\nMD")"
# heredoc 结束之后的真命令仍要抓到
t hard-deny "$(printf 'cat > d.md <<EOF\ntext\nEOF\ngit push')"

# 编码：deny 的 JSON 必须是合法 UTF-8 字节流。
# 单独列一条而不是靠上面的用例兜住 —— 上面测的是「分类对不对」，这条测的是
# 「输出能不能被 Claude Code 读进去」。分类全对但输出不是 UTF-8 时，守卫是
# 失败放行的，而失败放行比不装守卫更危险：它让人以为 push 被挡住了。
if mkjson "git push origin main" | "$PY" -S "$GUARD" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; then
  pass=$((pass+1))
else
  fail=$((fail+1))
  echo "  ✗ deny 输出不是合法 UTF-8 —— 守卫会静默失败放行"
  echo "    Windows 上多为 locale 编码(cp936)所致；worker_guard.py 应已用"
  echo "    sys.stdout.reconfigure(encoding='utf-8') 定死，检查那段是否生效"
fi

rm -f "$HOME/.claude/worker-guard/"*.queue "$HOME/.claude/worker-guard/"*.window 2>/dev/null
rmdir "$CLAUDE_PROJECT_DIR" 2>/dev/null
echo "通过 $pass / 失败 $fail"
[ "$fail" -eq 0 ]
