#!/usr/bin/env python3
"""k10-subagent-report — SubagentStop 钩子：第三者子代理的报告原样落盘，不经全局者转述。

WORKFLOW.md「K10 第三者」载体一节（堵「转述」漏洞 f）。挂在项目 .claude/settings.json 的
SubagentStop 事件上。只处理 agent_type 在 K10_AGENT_TYPES（空格分隔，默认 "skeptic verifier proposer"）
里的子代理；critic（验证者·安全专项）行为不变，不在默认名单里。
输出文件：.workflow/reports/<UTC 时间>-<agent_type>-<agent_id>.md，按 agent_id 分文件，不覆盖。
依赖：SubagentStop 输入里的 last_assistant_message（CC 2.1.283 实测存在）。缺这个字段时写一份
说明 + agent_transcript_path，不静默跳过。
"""
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

# Windows 本地编码是 GBK:CC 发来的 stdin 是 UTF-8,也按 UTF-8 解析我们的 stdout。
# 不重设就会乱码,CC 解析失败时静默放行(2026-09-29 MSI 实测)。
for _stream in (sys.stdin, sys.stdout, sys.stderr):
    _stream.reconfigure(encoding="utf-8")

TYPES = set(os.environ.get("K10_AGENT_TYPES", "skeptic verifier proposer").split())


def main():
    hook = json.load(sys.stdin)
    at = hook.get("agent_type", "")
    if at not in TYPES:
        print(f"[k10-subagent-report] {at or '(无 agent_type)'} 不在名单 {sorted(TYPES)}，跳过", file=sys.stderr)
        return 0
    proj = Path(os.environ.get("CLAUDE_PROJECT_DIR") or hook.get("cwd") or ".")
    out_dir = proj / ".workflow/reports"
    out_dir.mkdir(parents=True, exist_ok=True)
    aid = hook.get("agent_id", "noid")
    out = out_dir / f"{datetime.now(timezone.utc):%Y%m%dT%H%M%SZ}-{at}-{aid}.md"
    body = hook.get("last_assistant_message")
    if body is None:
        body = f"**钩子输入里没有 last_assistant_message**；transcript：{hook.get('agent_transcript_path')}"
    out.write_text(f"<!-- k10-subagent-report: agent_type={at} agent_id={aid} -->\n{body}\n", encoding="utf-8")
    print(f"[k10-subagent-report] 写入 {out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
