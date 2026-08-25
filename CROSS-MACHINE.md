# Cross-machine workflow

**[English](#english) · [中文](#中文)**

---

## English

The dual-model workflow in this repository (Overseer + Worker) is a **same-machine** protocol: two terminals, one disk, one `context.md`. Working across machines is a different thing, and the rules don't carry over unchanged. This document covers only the cross-machine part.

Day-to-day same-machine use doesn't need it. The line in `WORKFLOW.md` that says "this section assumes both terminals are on the same machine" points here.

### First decide whether you actually need a cross-machine handoff

Usually you don't. Work through these in order:

1. **Both machines work on the same git repository** → you need this. Read on.
2. **Each machine does its own thing and you just want to tell the other something once** ("I changed the shared config, heads up") → one message is enough. Don't build anything.
3. **Two different projects negotiating the same question over and over, across machines** → neither of the above. Use a dedicated channel repository; see [On a dedicated "message repository"](#on-a-dedicated-message-repository).
4. **Putting a project's Overseer on machine A and its Worker on machine B** → **don't**. That stretches the same-machine protocol past what it was built for: every handoff of `context.md` now has to round-trip through push/pull, and more breaks than you save. A Worker belongs on the same machine as its Overseer.

The normal cross-machine shape is **two Overseers talking to each other**, each with its own Worker at home. What crosses the wire is direction-alignment, not task assignment.

### Requirements

- **Both ends connected to Remote Control.** Miss one and the peer's row doesn't appear in `ListAgents` at all — that's not "sent but undelivered", it's not addressable.
- Versions: macOS / Linux / WSL 2 ≥ 2.1.224, native Windows ≥ 2.1.234.
- **Read the status column.** A dropped connection lingers in the listing as `offline`; a message sent there won't arrive. Only send to `idle` / `running` rows.

### The iron rule holds — the "file" just lives somewhere else

Same-machine, the rule is **a message only wakes the other side and points at the file; decisions always go into `context.md`**. Across machines this **still holds**, but the two machines share no disk —

> **The shared git repository is that disk.**

So a cross-machine handoff is three steps, not one:

1. Write `context.md` in the usual format
2. **`git push`**
3. Send a message that is a **pointer**:

   > Pushed to `origin/main`. The handoff block is the `[2026-08-25 14:30 +08:00]` entry in `context.md` — pull, then pick up via `/as-overseer`.

The receiving side: **`git pull` first, then read the file**, then run the full procedure. Never start work from the message's description of it.

**If the two machines share no repository**, first work out which case you're in: a one-off handoff that has nowhere to land means the work shouldn't have been split this way — take it back to your user. Sustained negotiation between two different projects is a different case and has its own answer, below. What is never right is forcing content through messages because there's nowhere to put it.

<h3 id="on-a-dedicated-message-repository">On a dedicated "message repository"</h3>

Two cases; don't conflate them.

**Same project, across machines → don't build one. Use the project repository.** The problem a dedicated message repository would solve is one the project repository already solves: it's on both machines, diffable, and traceable by construction. An extra repository means one more thing to pull, one more thing to forget to sync, and one more place that can disagree with `context.md` without telling you which to believe. **A handoff record that lives in a different repository from the code it describes is pure liability.**

**Two different projects, negotiating over the long haul → build one.** Here there is no shared project repository to fall back on, and the alternative in practice is a human copy-pasting between machines. That loses messages: in one real channel, two were lost, and both were errata — the one kind of message whose loss doesn't cost you information but leaves a known error alive in the other side's records under the guise of being correct. One letter per file per commit fixes that structurally: commits don't vanish, and a gap in the numbering is the alarm.

That is a different mechanism with its own protocol, not something this document defines. What carries over unchanged is the iron rule: **the letter goes in the repository, the message is only a pointer to it.**

On tokens: **the message isn't the expensive part — rebuilding context on the receiving end is.** A pointer message is a few hundred tokens, which rounds to nothing. The real cost is the receiver understanding the current state after reading the file, and that cost exists no matter what channel you use — which is exactly what the "Current State" block in `context.md` is there to compress.

Conversely, **if you find your messages getting longer and starting to carry content, the channel isn't too small — the process has drifted.** Content belongs in the file. The platform refuses oversized messages anyway.

### Addressing: the three-segment session name doesn't apply

Same-machine, you find the peer by the `<project-dir>-<role>-<topic>` prefix. **Across machines that scheme is not in play:**

- The peer shows up under its **Remote Control name** (something like `msi-linear-snail`), not the session name it was launched with.
- When you send, the peer sees **your** Remote Control name as the sender. Its reply goes to that name.
- So: **copy the `from` of the message you received** when replying. Don't assemble a name yourself.

### Linux ↔ Windows specifics

#### 1. Line endings (pinned at the repository level)

`.gitattributes` at the root sets `* text=auto eol=lf`, so both working trees are LF.

**Why this earns its own rule:** once line endings differ between the two ends, every handoff makes `context.md` diff as a whole-file change, and "what changed this round" becomes unreadable — and review in this workflow is done entirely by reading diffs. This isn't tidiness; the review mechanism fails outright.

A fresh clone needs nothing. An existing clone that already took on CRLF needs one `git add --renormalize .`.

#### 2. Write repository-relative paths only

In `context.md`, write `src/auth/login.ts`. **Not** `C:\Users\Haven\...` or `/root/workspace/...`. An absolute path doesn't exist on the other machine, so the model goes looking, fails to find it, and starts guessing.

#### 3. Timestamps carry a UTC offset

Same-machine projects keep the plain `[YYYY-MM-DD HH:MM]` format. **Cross-machine projects** may span two timezones (a VPS is usually UTC, a personal machine usually isn't), and appended history entries end up out of order:

```
## [2026-08-25 14:30 +08:00] Overseer
```

With the offset, neither the reader nor the model has to guess.

#### 4. Filename case

Windows filesystems are case-insensitive, Linux ones aren't. Two files differing only in case coexist on Linux and collide into one on Windows. Don't create such names.

#### 5. `security-scan.sh` runs under Git Bash on Windows

Claude Code ships Git Bash, so the precheck script runs on both ends with the same command.

#### 6. Prefer an HTTPS clone URL on a proxied Windows machine

A TUN-mode proxy client can intercept port 22 and hand SSH a fake IP, so `git clone git@github.com:…` fails with something like `Connection closed by 198.18.x.x port 22` — an address from the proxy's fake-IP range, not GitHub. An HTTPS clone goes through unchanged. If you want SSH anyway, GitHub also serves it on 443 via `ssh.github.com`.

### What doesn't work across machines

- **`notify_when_idle`** — the platform limits it to "your sessions on this machine". Subscribing to a peer's idle notice across machines isn't available; don't build it into a procedure.

### Content boundaries

Cross-machine messages are **relayed through Anthropic servers** (same-machine traffic goes over a local socket / named pipe and never leaves the machine). Two consequences:

1. **Keys, credentials, and anything that shouldn't leave never go in a message.** That material belongs in files and secret management, not in any channel.
2. **Sessions wired to a third-party model endpoint** (a Worker running a non-Anthropic model, say) still relay through Anthropic when messaging across machines. I have no authoritative basis for where the compliance line sits here and won't guess.

   In practice it doesn't come up: organize things as "cross-machine means two Overseers talking", keep Workers talking only to the Overseer on their own machine, and the question never arises. That constraint is correct on its own merits anyway — a Worker taking assignments across machines breaks the handoff chain at push/pull.

To require your approval for every cross-machine message, add to your settings:

```json
{ "isolatePeerMachines": true }
```

It prompts even under `bypassPermissions`.

---

## 中文

本仓库的双模型工作流（全局者 + 工作者）是**同机器**协议：两个终端、一块磁盘、一份 `context.md`。跨机器是另一回事，规则不能直接照搬。这份文档只管跨机器的部分。

日常同机使用不需要读本文。`WORKFLOW.md` 里那句「本节假设两个终端在同一台机器上」指向的就是这里。

### 先做一个判断：你真的需要跨机器交接吗

多数时候不需要。按这个顺序判断：

1. **两台机器在同一个 git 仓库上干活** → 需要，往下读。
2. **两台机器各干各的，只是想互相通知一声**（「我这边改了共享配置，你注意」）→ 一条消息就够了，不用建任何机制。
3. **两个不同项目、跨机器、就同一件事反复协商** → 上面两条都不适用，用专门的信道仓库，见[「要不要建一个专门的消息仓库」](#关于要不要建一个专门的消息仓库)。
4. **想把一个项目的全局者放 A 机、工作者放 B 机** → **不要这么做**。这是把同机协议硬拉长，`context.md` 每次交接都要过一遍 push/pull，出错的地方比省下的多。工作者应该和它的全局者在同一台机器上。

跨机器的正常形态是**两个全局者对话**：各自机器上带着自己的工作者，跨机器传的是「方向对齐」，不是「派活」。

---

### 前提

- **两端都连着 Remote Control**。缺一边，对方整行不出现在 `ListAgents` 里——不是"发了没到"，是根本寻不到址。
- 版本：macOS / Linux / WSL 2 ≥ 2.1.224，原生 Windows ≥ 2.1.234。
- **看状态列**。掉线的旧连接会以 `offline` 留在列表里，投过去不会到。只发 `idle` / `running` 的行。

---

### 铁律不变，只是「文件」换了个地方

同机的铁律是**消息只叫醒和指路，决策内容一律写 `context.md`**。跨机器这条**同样成立**，只是两台机器没有共享磁盘——

> **共享的 git 仓库就是那块磁盘。**

所以跨机器交接是三步，不是一步：

1. 按原格式写 `context.md`
2. **`git push`**
3. 发消息，消息体是**指针**：

   > 已推送到 `origin/main`，交接块见 `context.md` 的 `[2026-08-25 14:30 +08:00]` 条目，pull 后按 `/as-overseer` 流程接手。

收到方：**先 `git pull`，再读文件**，然后走完整流程。不要凭消息里的描述开始干活。

**如果两台机器没有共享仓库**，先分清是哪一类：一次性交接却无处落地，说明这件事本来就不该跨机器拆，回到用户那里；两个不同项目的长期协商是另一类，答案在下一节。**永远不对的是「没地方放所以塞进消息」。**

---

### 关于「要不要建一个专门的消息仓库」

分两种情况，别混为一谈。

**同一个项目跨机器 → 不要建，用项目仓库本身。** 专门的消息仓库要解决的问题，项目仓库已经解决了——它天然是两端都有、可 diff、可追溯的。多一个仓库意味着多一处要 pull、多一处会忘记同步、多一处和 `context.md` 说法不一致时不知道信谁。**交接记录和它描述的代码不在同一个仓库里，是纯粹的负债。**

**两个不同项目长期协商 → 建。** 这类信道没有共享项目仓库可依托，现实中的替代方案就是人工在两台机器之间转发——而人工转发会丢信。真实案例：一条跑了三周的信道丢过两封，**两封都是勘误**，而勘误是唯一一类「丢了不是少一条信息，而是让一条已知错误在对方档案里继续以正确身份存活」的消息。一封信一个文件一个 commit 能从结构上消掉它：commit 不会丢，编号断号就是告警。

那是另一套机制，有自己的协议，不由本文档定义。**不变的是铁律：信件进仓库，消息只是指向它的指针。**

至于 token：**消息本身不贵，贵的是接收方重建上下文。** 一条指针消息几百 token，可以忽略；真正的成本是接收方读完文件后要理解现状——那部分不管走什么通道都省不掉，而 `context.md` 的「当前状态」区块本来就是为压缩这个成本设计的。

反过来说，**如果你发现消息写得越来越长、开始塞内容进去，那不是通道不够用，是流程走样了**——内容该进文件。平台对超大消息本来也会直接拒发。

---

### 寻址：跨机器不用三段式会话名

同机靠 `<项目目录名>-<角色>-<话题>` 前缀找人。**跨机器这套不适用**：

- 对方在列表里显示的是它的 **Remote Control 名字**（形如 `msi-linear-snail`），不是它启动时设的会话名。
- 你发过去，对方看到的发件人也是**你这边的 Remote Control 名字**。它回信就是回给这个名字。
- 所以：**回复时直接抄收到消息的 `from`**，不要自己拼名字。

---

### Linux ↔ Windows 的具体差异

#### 1. 换行符（已在仓库层面钉死）

根目录的 `.gitattributes` 里是 `* text=auto eol=lf`，两端工作树统一 LF。

**为什么值得单独处理：** 换行符一旦两端不一致，每次交接 `context.md` 都会 diff 出整文件改动，「这一轮改了什么」就读不出来了——而这套工作流的复核**全靠读 diff**。这不是洁癖问题，是复核机制会直接失效。

新克隆的机器不用做任何事。已有克隆如果之前有 CRLF 混入，跑一次 `git add --renormalize .`。

#### 2. 路径只写仓库相对路径

`context.md` 里写 `src/auth/login.ts`，**不要**写 `C:\Users\Haven\...` 或 `/root/workspace/...`。绝对路径在对面那台机器上不存在，模型会去找、找不到、然后开始猜。

#### 3. 时间戳带 UTC 偏移

同机项目保持原格式 `[YYYY-MM-DD HH:MM]` 即可。**跨机器项目**两台机器时区可能不同（VPS 常年 UTC，个人机通常是本地时区），追加的历史条目会乱序：

```
## [2026-08-25 14:30 +08:00] 全局者
```

带上偏移，读的人和模型都不用猜。

#### 4. 文件名大小写

Windows 文件系统大小写不敏感，Linux 敏感。两个只差大小写的文件在 Linux 上共存、到 Windows 上会撞成一个。别造这种文件名。

#### 5. `security-scan.sh` 在 Windows 上走 Git Bash

Claude Code 自带 Git Bash，预检脚本两端都能跑，命令一样。

#### 6. 走代理的 Windows 机器优先用 HTTPS clone

TUN 模式的代理客户端会接管 22 端口并给 SSH 一个 fake-IP，`git clone git@github.com:…` 于是报 `Connection closed by 198.18.x.x port 22` —— 那个地址来自代理的 fake-IP 段，不是 GitHub。换 HTTPS 直接就通。一定要用 SSH 的话，GitHub 在 443 上也有 `ssh.github.com`。

---

### 跨机器用不了的东西

- **`notify_when_idle`**——平台限定「only to your sessions on this machine」。跨机器订阅对方空闲通知这条路不通，别写进流程。

---

### 内容边界

跨机器消息**经 Anthropic 服务器中转**（同机走本地 socket / 命名管道，不出机器）。两个后果：

1. **密钥、凭据、不该外发的内容一律不进消息。** 这类东西本来就该进文件、进密钥管理，不该在任何通道里传。
2. **接入了第三方模型端点的会话**（比如工作者跑的是非 Anthropic 模型），跨机器发消息时消息仍然走 Anthropic 的中转。这里的合规边界我没有确切依据，不做判断。

   实践上不需要纠结：按上面「跨机器的正常形态是两个全局者对话」来组织，工作者只和同机的全局者说话，这个问题不会出现。这条约束本来就是对的——工作者跨机器接活，交接链会断在 push/pull 上。

需要每条跨机消息都先经你人工批准的话，设置里加：

```json
{ "isolatePeerMachines": true }
```

即使在 `bypassPermissions` 模式下也会照样弹确认。
