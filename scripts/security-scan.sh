#!/usr/bin/env bash
# 双模型工作流 — 安全敏感 diff 预检（纯本地 grep，零 token 消耗）
#
# 用途: 全局者审查工作者输出前运行。不依赖工作者「关键决策点」自报，
#       对 diff 新增行做客观关键词扫描，命中即强制走 critic/security-reviewer 审查。
#
# 用法:
#   security-scan.sh            # 扫描未提交改动（相对 HEAD，含 staged + unstaged）
#   security-scan.sh <base>     # 额外扫描 <base>..HEAD 的已提交改动
#   只扫当前目录这棵子树（`-- .`）：项目可能是大仓库里的一个子目录，在项目根目录跑
#
# 退出码: 0 = 未命中；1 = 命中（必须 invoke 安全审查子代理）；
#         2 = 没跑成：不在 git 工作树里（含 .git 目录内、裸仓库）、还没有提交、<base> 不是一个 commit（含空串）、参数多于 1 个
#         （2 不是「未命中」。下面的 git diff 把报错丢进 /dev/null，所以这些前提必须先查，否则坏 ref 会静默变成 0）
#
# 注意: 只打印 file:line + 命中的关键词本身，永不输出整行内容（避免本脚本成为密钥泄露源）。
set -uo pipefail

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "[security-scan] 当前目录不是 git 仓库" >&2
  exit 2
fi
if [ "$(git rev-parse --is-inside-work-tree 2>/dev/null)" != true ]; then
  echo "[security-scan] 当前目录不在 git 工作树里（.git 目录内或裸仓库），diff 跑不了，预检没跑成" >&2
  exit 2
fi

if [ "$#" -gt 1 ]; then
  echo "[security-scan] 用法: security-scan.sh [<base>]（只收 1 个参数，收到 $# 个），预检没跑成" >&2
  exit 2
fi
BASE="${1:-}"
if ! git rev-parse --verify -q HEAD >/dev/null; then
  echo "[security-scan] 仓库还没有提交（HEAD 不存在），对 HEAD 的 diff 跑不了，预检没跑成" >&2
  exit 2
fi
if [ "$#" -eq 1 ] && ! git rev-parse --verify -q "$BASE^{commit}" >/dev/null; then  # 按参数个数判，空串也要报
  echo "[security-scan] <base>「$BASE」不是一个 commit，预检没跑成" >&2
  exit 2
fi

# 分类关键词（大小写不敏感，只扫代码/配置，排除 .md 文档）
# 认证/会话 | 密钥凭据 | 注入/命令执行 | 路径穿越/权限 | 外部请求
PATTERN='auth|login|jwt|cookie|passw(or)?d|secret|token|api[_-]?key|credential|private[_-]?key|\.env([^A-Za-z0-9_]|$)|select .+ from|insert into|delete from|drop table|exec\(|execute\(|eval\(|spawn|subprocess|os\.system|shell=true|child_process|\.\./|chmod|chown|sudo |http://|https://|fetch\(|requests\.(get|post|put|delete)|axios\.|curl |wget |ssh |scp |iptables'

EXCLUDES=(':(exclude)*.md' ':(exclude)context*.md' ':(exclude)WORKFLOW.md')

collect_diff() {
  git diff -U0 HEAD -- . "${EXCLUDES[@]}" 2>/dev/null
  if [ -n "$BASE" ]; then
    git diff -U0 "$BASE"..HEAD -- . "${EXCLUDES[@]}" 2>/dev/null
  fi
}

export PATTERN
HITS=$(collect_diff | awk '
  BEGIN { IGNORECASE = 1; pat = ENVIRON["PATTERN"] }
  /^\+\+\+ / { file = substr($0, 7); sub(/^b\//, "", file); next }
  /^@@ /     { split($0, a, " "); split(a[3], b, ","); line = substr(b[1], 2) + 0; next }
  /^\+/ && !/^\+\+\+/ {
    if (match($0, pat)) {
      print file ":" line ": " substr($0, RSTART, RLENGTH)
    }
    line++
  }
')

# 未跟踪的新文件不在 git diff 里，单独扫描（工作者新建文件是常见场景）
UNTRACKED_HITS=$(git ls-files --others --exclude-standard -- . ':(exclude)*.md' \
  | while IFS= read -r f; do
      [ -f "$f" ] || continue
      grep -inoE "$PATTERN" -- "$f" 2>/dev/null | head -20 | sed "s|^|$f:|"
    done)

if [ -n "$UNTRACKED_HITS" ]; then
  HITS="${HITS:+$HITS
}$UNTRACKED_HITS"
fi

# 无条件印出扫了什么，未命中和命中都印：「未命中」只在这个范围内成立
SCOPE="子树 $(git rev-parse --show-prefix 2>/dev/null)"; [ "$SCOPE" = "子树 " ] && SCOPE="仓库根"
echo "[security-scan] 范围：${SCOPE}；未提交改动 + 未跟踪文件${BASE:+ + ${BASE}..HEAD 的已提交改动}"
if [ -z "$HITS" ]; then
  echo "[security-scan] ✅ 未命中安全敏感关键词，可按常规流程审查"
  exit 0
fi

COUNT=$(printf '%s\n' "$HITS" | wc -l)
echo "[security-scan] ⚠️  命中 $COUNT 处安全敏感改动（file:line: 关键词）:"
printf '%s\n' "$HITS" | sort -u | head -50
if [ "$COUNT" -gt 50 ]; then echo "  ...（仅显示前 50 处）"; fi
echo ""
echo "[security-scan] → 必须 invoke critic / security-reviewer 对相关文件做结构化审查，不得仅凭工作者摘要放行"
exit 1
