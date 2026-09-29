#!/usr/bin/env python3
"""k10-stop-gate — Stop 钩子：第三者报告已写出、全局者还没回应时，不许全局者结束回合。

WORKFLOW.md「K10 第三者」的「强制回应」。挂在项目 .claude/settings.json 的 Stop 事件上。
- 只拦全局者：看环境变量 DUAL_MODEL_ROLE（启动器 cc / cc-alt 设置）。不是 overseer 就放行。
- 报告：.workflow/reports/*.md；回应：.workflow/responses/<同名>.md。
- 判据：报告里出现的每个意见编号（S1、S2……），在回应文件里都要有一行同时含该编号和
  「接受 / 驳回 / 部分接受 / 交用户」之一。报告里一个编号都没有时，只要求回应文件存在。
  这是**格式**检查，不是「逐条认真回应」的保证：一行「S1 S2 S3 接受」就能满足全部编号。
- 防死循环：同一回合内（CC 的 stop_hook_active 为真）连续拦截到 MAX_BLOCKS 次后放行，
  放行时用 systemMessage 告诉用户缺口仍在。新回合（stop_hook_active 为假）计数从 1 重新开始，
  所以每个回合都会重新被拦。计数状态在 .workflow/k10-gate.json。
- `--check`：只读检查，给 /as-overseer 每轮复述用。不读 stdin、不写状态、不输出拦截 JSON，
  只在 stdout 打印缺口（2026-09-26 实测：手动跑拦截模式会把计数耗光，见 verifier 第十轮 B）。
输出：stderr 永远有一行「查了 N 份报告，未回应 M 份」。
"""
import json
import os
import re
import sys
from pathlib import Path

# Windows 本地编码是 GBK:CC 发来的 stdin 是 UTF-8,也按 UTF-8 解析我们的 stdout。
# 不重设就会乱码,CC 解析失败时静默放行(2026-09-29 MSI 实测)。
for _stream in (sys.stdin, sys.stdout, sys.stderr):
    _stream.reconfigure(encoding="utf-8")

MAX_BLOCKS = int(os.environ.get("K10_GATE_MAX_BLOCKS", "3"))
VERDICT = re.compile(r"接受|驳回|交用户")
ID = re.compile(r"(?<![A-Za-z0-9])S(\d+)(?![0-9])")


def missing_for(report, response):
    ids = sorted(set(ID.findall(report.read_text(encoding="utf-8", errors="replace"))), key=int)
    if not response.exists():
        return ["(无回应文件)"]
    lines = response.read_text(encoding="utf-8", errors="replace").splitlines()
    return [f"S{i}" for i in ids
            if not any(re.search(rf"(?<![A-Za-z0-9])S{i}(?![0-9])", l) and VERDICT.search(l) for l in lines)]


def find_gaps(proj):
    reports = sorted((proj / ".workflow/reports").glob("*.md"))
    gaps = {}
    for r in reports:
        m = missing_for(r, proj / ".workflow/responses" / r.name)
        if m:
            gaps[r.name] = m
    print(f"[k10-stop-gate] 查了 {len(reports)} 份报告，未回应 {len(gaps)} 份", file=sys.stderr)
    return gaps


def describe(proj, gaps):
    # 路径一律写绝对路径：2026-09-26 实测，写相对路径时，模型按钩子脚本所在目录去猜项目位置，写错了地方。
    rep, res = proj / ".workflow/reports", proj / ".workflow/responses"
    return "；".join(f"{rep / k} 缺 {', '.join(v)} → 回应写到 {res / k}" for k, v in gaps.items())


def main():
    check_only = "--check" in sys.argv[1:]
    hook = {}
    if not check_only:
        try:
            hook = json.load(sys.stdin)
        except json.JSONDecodeError:
            hook = {}
        if os.environ.get("DUAL_MODEL_ROLE") != "overseer":
            return 0
    proj = Path(os.environ.get("CLAUDE_PROJECT_DIR") or hook.get("cwd") or ".").resolve()
    gaps = find_gaps(proj)
    if check_only:
        if gaps:
            print(describe(proj, gaps))
        return 0
    state_p = proj / ".workflow/k10-gate.json"
    if not gaps:
        if state_p.exists():
            state_p.unlink()
        return 0
    key = json.dumps(gaps, ensure_ascii=False, sort_keys=True)
    try:
        state = json.loads(state_p.read_text(encoding="utf-8")) if state_p.exists() else {}
    except (json.JSONDecodeError, OSError):
        state = {}
    same_turn = bool(hook.get("stop_hook_active"))
    count = state.get("count", 0) + 1 if (same_turn and state.get("key") == key) else 1
    if count > MAX_BLOCKS:
        msg = f"K10 强制回应：本回合已拦 {MAX_BLOCKS} 次，这次放行，但缺口仍在——{describe(proj, gaps)}"
        print(f"[k10-stop-gate] {msg}", file=sys.stderr)
        print(json.dumps({"systemMessage": msg}, ensure_ascii=False))
        return 0
    state_p.parent.mkdir(parents=True, exist_ok=True)
    state_p.write_text(json.dumps({"key": key, "count": count}, ensure_ascii=False), encoding="utf-8")
    print(json.dumps({"decision": "block", "reason":
        f"K10 强制回应：以下第三者报告还没回应：{describe(proj, gaps)}。"
        f"回应文件里，每个意见编号写一行，同一行里要有编号和「接受 / 驳回 / 部分接受 / 交用户」之一，再加理由；"
        f"只处理上面列出的报告，不要去别处找，也不要自己制造报告。写完再结束回合。"
        f"（本回合第 {count}/{MAX_BLOCKS} 次拦截）"}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
