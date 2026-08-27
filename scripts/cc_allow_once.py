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

# Windows 上 Python 的管道输出默认走 locale 编码（简中系统是 cp936），而本文件
# 的 deny reason 全是中文。Claude Code 按 UTF-8 解析钩子 stdout，解析失败会丢掉
# permissionDecision —— 守卫**静默失败放行**，这是它最坏的失效方式。
# 在脚本里定死，而不是靠钩子命令写对 -X utf8：调用方式有好几种，脚本只有一份。
try:
    sys.stdout.reconfigure(encoding="utf-8")
except (AttributeError, ValueError):
    pass


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
