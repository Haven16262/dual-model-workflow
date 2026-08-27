#!/usr/bin/env python3
"""开启放行窗口并打印待批准队列。

只由 /allow-once 这个 skill 的 `!` 行调用——那一步在模型看到任何东西之前执行，
所以开窗是「用户在场」的信号，模型无法自己发出。

开窗 != 授权：窗口只让弹窗能弹出来，权限仍然来自用户在弹窗上点的那一下。
"""
import os, sys, time, hashlib

GUARD_DIR = os.path.expanduser("~/.claude/worker-guard")
WINDOW_SECONDS = 600
QUEUE_MAX_AGE = 86400


def main():
    project = os.environ.get("CLAUDE_PROJECT_DIR") or os.getcwd()
    key = hashlib.md5(os.path.abspath(project).encode("utf-8")).hexdigest()[:10]
    q = os.path.join(GUARD_DIR, key + ".queue")
    win = os.path.join(GUARD_DIR, key + ".window")

    os.makedirs(GUARD_DIR, exist_ok=True)
    expiry = time.time() + WINDOW_SECONDS
    with open(win, "w") as f:
        f.write("%f\n" % expiry)

    print("窗口已开 → %s 失效（%d 分钟）"
          % (time.strftime("%H:%M", time.localtime(expiry)), WINDOW_SECONDS // 60))

    entries = []
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
                    entries.append((ts, cmd))
    except OSError:
        pass

    if not entries:
        print("")
        print("当前项目没有待批准队列。")
        print("（若这是全局者会话，本命令对它无效——守卫只装在工作者会话上。）")
        return

    print("")
    print("待批准 (%d)：" % len(entries))
    for i, (ts, cmd) in enumerate(entries, 1):
        print("  %d. %-52s %s" % (i, cmd, time.strftime("%H:%M", time.localtime(ts))))


main()
