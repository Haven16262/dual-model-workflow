# Channel starter

A minimal kit for a **long-lived letter channel** between two projects (or two machines) that share no project repository: a layout, a letter template, and a gate script that tells the reader whether the channel is intact.

**[English](#english) · [中文](#中文)**

---

## English

### When to use this — and when not to

Read [`../CROSS-MACHINE.md`](../CROSS-MACHINE.md) first. In short:

- **Two machines working on the same project** → no channel repository; the project repository is the channel.
- **Two different projects negotiating the same questions over a long time, with no shared repository** → this kit. The usual alternative is a human copying text between machines, and that loses messages.

The channel carries letters. *How you tell the other side a letter exists* (a chat message, e-mail, a webhook, Claude Code's `SendMessage`, anything) is up to you — see "The pointer message" below.

This kit was distilled from a private channel that ran between two of the author's machines. The conventions below are the ones that survived real use; the letters themselves are not published.

### The one rule behind everything

> **A letter goes into the repository. The message only points at it.**

Messages are ephemeral; anything that never reaches a file did not happen. Git makes the file side robust: commits do not vanish, and a numbering gap is visible at a glance.

### Layout

```
channels/
  alice--bob/                      ← permanent channel between two projects:  <a>--<b>
    INDEX.md                       ← append-only, one "- NNNN ..." line per letter
    0001-alice-notice-before-open-port.md
    0002-bob-reply-open-port.md
    0003-alice-erratum-fix-port-number.md
  20260110-new-protocol/           ← topic channel that will be closed:  <YYYYMMDD>-<topic>
scripts/
  check-channel.sh                 ← the reader's gate
  test-check-channel.sh
TEMPLATE.md                        ← copy this for every new letter
```

Two kinds of channel, one difference: **does it end?** A permanent channel is named after the pair (`a--b`); a topic channel carries its start date and is archived as a whole when closed. Letters, numbering, errata and the gate are identical for both. Let the name carry the classification instead of adding sub-directories.

File name: `NNNN-<from>-<type>-<slug>.md`.

- **NNNN** — four digits, increasing per channel, never reused, never skipped. A gap means a lost letter.
- **from** — a short project name (letters, digits, underscore). No person or machine names.
- **type** — one of five (below).
- **slug** — human-readable; say what the letter is about, not "reply" or "update". Any language is fine.

### Letter types

| Type | Use it for |
|---|---|
| `notice-before` | a **planned** change, sent before you act; the other side answers before you proceed |
| `notice-after` | an **unplanned** interruption or a fact that has already happened, sent as soon as possible |
| `reply` | answering a letter |
| `erratum` | correcting one of **your own** earlier letters |
| `closure` | this topic is finished; no answer needed |

Planned = before, unplanned = after.

### Errata are independent letters (the most important rule)

**A sent letter is never edited.** If you find you were wrong, send a new, separately numbered letter of type `erratum` with `corrects: <number>`.

Why: an erratum folded into an ordinary reply is the easiest thing to skip, and it is also the one kind of message whose loss does not merely cost information — it leaves a *known* error alive in the other side's records, looking correct. In the channel this kit comes from, the letters that were lost were all errata. Giving an erratum its own number makes it impossible to lose quietly.

Do not go back and edit a committed letter either: the other side may already have read the old version, and two diverging truths are worse than one wrong one. The gate reports a letter that was touched by more than one commit.

### One letter = one file = one commit

1. Copy `TEMPLATE.md`, fill the front matter completely.
2. Append one line to the channel's `INDEX.md`: `- NNNN <type> <title>`.
3. `git add` those two files and commit: `NNNN <type>: <title>`.
4. `git push`, then send the pointer message.

Front-matter rules the gate enforces: all eight keys present; `seq` and `type` equal the ones in the file name; `date` carries a UTC offset (two machines, two time zones — without it history sorts wrongly); `needs_reply` is `true` or `false`; `replies_to` and `corrects` point at **earlier letters that exist**; only an erratum has `corrects` set. If `needs_reply: true`, end the letter by naming the exact question.

### The pointer message

Say that a letter exists and where — nothing more. **The first message about a channel must carry the clone URL or the other side's local path**: a pointer that cannot be resolved is worse than a pasted summary, because the summary can at least be read. Give each side a clone URL it can actually reach (HTTPS on one machine, SSH on another is fine; do not assume SSH everywhere).

### The gate: the reader runs it

```bash
git pull
scripts/check-channel.sh        # then read the new letters
```

The **reader** runs it, not the author. An author can skip his own gate, but cannot skip the fact that the other side is about to read the letter.

It checks, per channel: file names, duplicate numbers, gaps from 0001, `INDEX.md` against the letters in both directions, the front matter above, and (inside a git work tree) letters changed after their first commit. Exit codes: `0` all passed, `1` problems found, `2` it could not decide (no `channels/`, or no channel inside it).

Design rules it follows, worth keeping if you extend it:

- **It never says "nothing new".** It prints how many letters in how many channels it looked at, or it exits non-zero. A check whose success message could be printed without checking anything carries no signal.
- **A check that is always red carries no signal either.** Do not make it fail on conditions you cannot clear.
- **Do not rely on a git hook to run it.** If `core.hooksPath` is set anywhere (for example globally), repository-level hooks are silently ignored, and the check is then green because it never ran. Make running the gate a step of the receiving procedure.
- Reconcile in both directions. When comparing "what A has" with "what B has", report the difference both ways; a one-way diff produces a confident "only one is missing" that is wrong.

Run `bash scripts/test-check-channel.sh` to see the gate's own tests (30 cases).

### Archive

When a topic ends, move its letters (or the whole topic directory) into `archive/` and mark the lines in `INDEX.md` as archived. Numbers are never recycled.

### Don't

- Don't put content in the message; put it in the letter.
- Don't edit a sent letter; write an erratum.
- Don't put keys or credentials in a letter, private repository or not.
- Don't skip or reuse numbers; the gap is the only alarm you have.
- Don't use a channel repository for two machines on the same project.

---

## 中文

### 什么时候用,什么时候不用

先读 [`../CROSS-MACHINE.md`](../CROSS-MACHINE.md)。简单说:

- **两台机器做同一个项目** → 不建信道仓库,项目仓库本身就是信道。
- **两个不同项目、没有共同仓库、要长期反复协商同一件事** → 用这套。通常的替代做法是人在两台机器之间复制粘贴,而那会丢信。

信道只负责「信」。**怎么通知对方有一封信**(聊天消息、邮件、webhook、Claude Code 的 `SendMessage`,什么都行)由你决定,见下面「指针消息」。

这套东西提炼自作者两台机器之间一条私有信道的实际使用。下面的约定是经得起真实使用的那部分,信件本身不公开。

### 一切背后的一条规则

> **信进仓库,消息只指路。**

消息是易失的,没有进文件的东西等于没有发生。git 让文件这一侧很稳:commit 不会丢,编号断号一眼就能看出来。

### 目录布局

```
channels/
  alice--bob/                      ← 常驻信道,两个项目之间:  <甲>--<乙>
    INDEX.md                       ← 只追加,一行一封「- NNNN ...」
    0001-alice-notice-before-open-port.md
    0002-bob-reply-open-port.md
    0003-alice-erratum-fix-port-number.md
  20260110-new-protocol/           ← 会结案的议题信道:  <YYYYMMDD>-<题名>
scripts/
  check-channel.sh                 ← 读方的闸门
  test-check-channel.sh
TEMPLATE.md                        ← 每封新信从这里复制
```

两类信道只有一个差别:**会不会结束。** 常驻信道以「这一对」命名(`甲--乙`);议题信道带开始日期,结案后整条归档。信件、编号、勘误、闸门完全相同。让名字承担分类,不要再加子目录。

文件名:`NNNN-<发信方>-<类型>-<短标题>.md`。

- **NNNN**——四位数字,按信道递增,不复用、不跳号。断号就是丢信。
- **发信方**——项目短名(字母、数字、下划线),不写人名机名。
- **类型**——五种之一(见下)。
- **短标题**——给人看的,写清这封在谈什么,别写「回复」「更新」。可以用中文。

### 信件类型

| 类型 | 用途 |
|---|---|
| `notice-before` | **计划内**变更,动手前发;对方回复之前你不动手 |
| `notice-after` | **非计划**的中断或已经发生的事实,尽快发 |
| `reply` | 回应某封信 |
| `erratum` | 更正**自己**以前发出的某封信 |
| `closure` | 这个议题到此为止,不需要回复 |

计划内 = 事前,非计划 = 事后。

### 勘误是独立的信(最重要的一条)

**已发出的信永不修改。** 发现自己错了,发一封新的、独立编号的 `erratum`,`corrects: <编号>`。

原因:折进普通回复里的勘误最容易被跳过,而它恰恰是唯一一类「丢了不只是少一条信息」的消息——它让一条**已知**的错误在对方档案里继续以正确的样子存活。这套东西来源的那条信道里,丢掉的信全是勘误。给勘误单独编号,就不可能悄悄丢掉。

也不要回头改已经提交的信:对方可能已经读过旧版,两份分叉的真相比一份错的更糟。闸门会报出被多于一个提交改动过的信。

### 一封信 = 一个文件 = 一个 commit

1. 复制 `TEMPLATE.md`,把前置元数据填全。
2. 在该信道的 `INDEX.md` 追加一行:`- NNNN <类型> <标题>`。
3. 这两个文件 `git add` 后提交:`NNNN <类型>: <标题>`。
4. `git push`,然后发指针消息。

闸门检查的元数据规则:八个键都在;`seq` 和 `type` 与文件名一致;`date` 带 UTC 偏移(两台机器两个时区,不带偏移历史会乱序);`needs_reply` 只能是 `true` 或 `false`;`replies_to`、`corrects` 指向**已存在的更早的信**;只有 `erratum` 才设 `corrects`。`needs_reply: true` 时,信末要写明具体要对方回答什么。

### 指针消息

只说有一封信、在哪,不多说。**第一次谈到某条信道的消息必须带 clone URL 或对端的本地路径**:解析不了的指针比一段复述更糟,因为复述至少还能读。给每一端它真能访问的 clone 地址(一台用 HTTPS、一台用 SSH 都可以,别假定处处能走 SSH)。

### 闸门:读方来跑

```bash
git pull
scripts/check-channel.sh        # 然后再读新信
```

由**读方**来跑,不是作者。作者可以选择不跑自己的闸门,但漏不掉对方要读这封信这件事。

它按信道检查:文件名、重号、从 0001 起的断号、`INDEX.md` 与信件双向对账、上面的元数据规则,以及(在 git 工作区里)首次提交之后又被改动的信。退出码:`0` 全过,`1` 有问题,`2` 无法判定(没有 `channels/`,或里面没有信道)。

它遵循的设计规则,你扩展时值得保留:

- **它从不说「没有新东西」。** 只输出「查了几封、几条信道」,否则非零退出。一条不查就能打印出来的成功信息没有信号。
- **永远报警的检查同样没有信号。** 别让它在你清不掉的条件上失败。
- **不要靠 git 钩子来触发它。** 只要任何一级设了 `core.hooksPath`(比如全局设),仓库级钩子会被静默忽略,检查就会因为根本没跑而是绿的。把「跑闸门」写进收信流程。
- 对账要双向。比较「甲有什么」和「乙有什么」时两个方向的差都要报,单向差集会给出「只差一件」的错误结论。

`bash scripts/test-check-channel.sh` 可以跑闸门自己的测试(30 个用例)。

### 归档

议题结案后,把它的信(或整个议题目录)移进 `archive/`,`INDEX.md` 里对应行标记已归档。编号不回收。

### 不要做的事

- 不要在消息里传内容,内容放信里。
- 不要修改已发出的信,发勘误。
- 不要把密钥、凭据写进信里,私有仓库也不行。
- 不要跳号或复用编号,断号是你唯一的告警。
- 不要把信道仓库用在同一个项目的两台机器上。
