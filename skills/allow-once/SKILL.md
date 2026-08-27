---
name: allow-once
description: 开启 10 分钟放行窗口，让工作者被守卫拦下的命令能够弹窗等你批准
disable-model-invocation: true
allowed-tools: Bash(python3 -S ~/.claude/scripts/cc_allow_once.py)
---

!`python3 -S ~/.claude/scripts/cc_allow_once.py`

上面是当前的放行窗口和待批准队列。

如果队列非空：把队列里的命令**逐条重试**，一次一条，等每条的弹窗被批准后再跑下一条。
如果队列为空：不要做任何事，告诉用户当前没有待批准的命令。

窗口到期后守卫会恢复拦截，不需要你做任何清理。
