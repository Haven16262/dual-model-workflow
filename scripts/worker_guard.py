#!/usr/bin/env python3
"""PreToolUse 守卫：只加载给工作者会话（cc-ds 经 --settings 传入）。

把「会弹窗、但没人能批准」的命令，在弹窗打开之前拦掉。权限弹窗不会超时，
工作者一旦弹出来就是无限期挂死；拦在前面它才能跳过去做别的。

拦截集合刻意与全局 settings.json 的 ask 规则对齐——那三条才是弹窗来源。
"""
import sys, json, os, re, time, hashlib

GUARD_DIR = os.path.expanduser("~/.claude/worker-guard")
TAG_FILE = os.path.expanduser("~/.claude/machine-tag")
WINDOW_SECONDS = 600
QUEUE_MAX_AGE = 86400
NOTIFY_THRESHOLD = 3

# 硬拒：结构上不属于工作者，没有放行通道。
HARD_DENY = [(re.compile(r"\bgit\b[^\n]*\bpush\b"), "git push")]
# 拒 + 逃生舱：可能真是工作者的活，等用户在场时放行。
HATCH = [(re.compile(r"\bssh[ \t]"), "ssh"),
         (re.compile(r"\bchmod[ \t]"), "chmod")]


def machine_tag():
    try:
        with open(TAG_FILE) as f:
            return f.read().strip() or "?"
    except OSError:
        return "?"


def project_key(d):
    return hashlib.md5(os.path.abspath(d).encode("utf-8")).hexdigest()[:10]


def paths(d):
    k = project_key(d)
    return (os.path.join(GUARD_DIR, k + ".queue"),
            os.path.join(GUARD_DIR, k + ".window"))


def window_open(win):
    try:
        with open(win) as f:
            return time.time() < float(f.read().strip())
    except (OSError, ValueError):
        return False


def read_queue(q):
    """返回 [(epoch, command)]，顺带丢弃过期条目。"""
    out = []
    try:
        with open(q, encoding="utf-8") as f:
            for line in f:
                if line.startswith("#") or "\t" not in line:
                    continue
                ts, cmd = line.rstrip("\n").split("\t", 1)
                try:
                    ts = float(ts)
                except ValueError:
                    continue
                if time.time() - ts < QUEUE_MAX_AGE:
                    out.append((ts, cmd))
    except OSError:
        pass
    return out


def write_queue(q, entries, project):
    os.makedirs(GUARD_DIR, exist_ok=True)
    with open(q, "w", encoding="utf-8") as f:
        f.write("# %s\n" % project)
        for ts, cmd in entries:
            f.write("%f\t%s\n" % (ts, cmd))


def deny(reason):
    json.dump({"hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": reason}}, sys.stdout, ensure_ascii=False)
    sys.exit(0)


def main():
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)
    if data.get("tool_name") != "Bash":
        sys.exit(0)
    cmd = (data.get("tool_input") or {}).get("command", "")
    if not cmd:
        sys.exit(0)

    project = os.environ.get("CLAUDE_PROJECT_DIR") or data.get("cwd") or os.getcwd()
    q, win = paths(project)

    for pat, label in HARD_DENY:
        if pat.search(cmd):
            deny(
                "`%s` 不属于工作者职责，不会执行，也没有放行通道。\n\n"
                "正确做法：\n"
                "1. 确保工作已 commit\n"
                "2. 把当前状态写进 context.md（分支、commit 数、待复审的点）\n"
                "3. 通知全局者交接——由它复审后决定是否发布\n\n"
                "不要请求全局者代跑这条命令。交接的是工作，不是命令。" % label)

    for pat, _ in HATCH:
        if not pat.search(cmd):
            continue
        entries = read_queue(q)
        if window_open(win):
            # 放行即出队，用户不必手动清理。
            left = [e for e in entries if e[1] != cmd]
            if len(left) != len(entries):
                write_queue(q, left, project)
            sys.exit(0)
        if all(c != cmd for _, c in entries):
            entries.append((time.time(), cmd))
        write_queue(q, entries, project)
        deny(
            "`%s` 被守卫拦下（未执行）。已记入待批准队列，当前共 %d 条。\n\n"
            "现在做两件事：\n"
            "1. 在你的回复里直接说明需要跑这条命令，以及用户可以敲 /allow-once 放行\n"
            "   ——用户可能就在旁边，别让他等你稍后才提\n"
            "2. 继续做其他不依赖它的工作\n\n"
            "叫人的时机：没有其他可推进的工作了，或队列已积到 %d 条以上。\n"
            "这时才通知全局者，消息里带上机器名「%s」、队列条数、这批要确认什么。\n"
            "不要每拦一条就叫一次。" % (cmd, len(entries), NOTIFY_THRESHOLD, machine_tag()))

    sys.exit(0)


main()
