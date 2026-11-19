#!/usr/bin/env python3
"""handoff-check — 工作者交接块的机械核对（WORKFLOW.md「工作者写入「本 Phase 历史」」「切换触发条件」里能由脚本判的部分）。

用法: handoff-check.py [context.md 路径，默认 ./context.md] [--no-git] [--fresh 分钟] [--now "YYYY-MM-DD HH:MM"]
  在项目根目录跑。工作者写完交接块、说切换话术之前跑一次；全局者接手时（/as-overseer 第 4 步）再跑一次。
  --no-git   不查提交与工作树（只查 context.md 里的文字）；测试和只读审计用
  --fresh N  另查：交接块时间戳距现在不超过 N 分钟（工作者交接时用 120；全局者复查时不带）
  --now      测试用，替代当前时间（本机时区）

查的是「最后一条工作者条目」（标题含「工作者」的最后一个 `## [时间]` / `### [时间]`），逐项。条目边界与标题识别不看代码围栏里的行
（闸门输出里 `git status -sb` 的第一行就是 `## main...origin/main`，不能当成下一个条目）；git 命令在 context.md 所在目录跑（不是当前目录）：
  H0  最后一条工作者条目之后不能再有别的条目：已有全局者条目，说明这一轮没有新的工作者交接块（新块没写，或标题格式写错——漏中括号、
      `####`、没写「工作者」——于是脚本落回上一轮已通过的旧块）；之后出现标题像时间戳条目、却认不出是工作者条目的，同样报
  H1  标题时间戳能解析；不晚于现在 +15 分钟；不早于上一条条目（两条都带同一时区后缀或都不带时才比）；--fresh 时距现在不超过 N 分钟。
      标题里的时区后缀（UTC、UTC+8、+08:00、Z）先换算成本机时间再和「现在」比；认不出的后缀（如 CST，有歧义）不和现在比，在末行「跳过」里写明
  H2  完成阶段块（含「完成情况」，仅此类块查）：开头有「提交：`<sha>`」或「提交：无（原因）」；有 sha 时 git 认它是 commit 且是 HEAD 的祖先
  H3  完成阶段块：「闸门结果」「spec 修正」「关键决策点」三个标签都在；「关键决策点」之后四个关键词（架构/接口变动、安全相关、偏离原计划、未解决的疑虑）都出现
  H4  「闸门结果」不是「无」时，其中至少有一处 rc=<数字>（逐条是否都有 rc，机械判不了，只查「一处都没有」）
  H5  非完成阶段块（没有「完成情况」）：「问题」「已尝试」「需要决策」三个标签都在
  H6  「## 当前状态」里有「未验证的前提」和「backlog」两行（行首标签；去掉 HTML 注释后判；省略和写「无」是两回事）
  H7  完成阶段块才查：工作树除 context*.md、sessions.md 外没有未提交改动（完成阶段交接前必须先提交）。非完成阶段块（触发切换时）
      常有未提交的半成品，不查 H7
  H8  交接块里没有以 workflow-mode: 开头的行（含缩进、workflow_mode、全角冒号、大小写变体）：整个 context.md 只许「当前状态」里有那一行，
      别处写成「模式：competition」，否则启动器（dual-model-mode.sh）会拒绝启动
不查（机械判不了，写在这里免得被当成查过）：交接块内容是否属实、闸门原始输出是否真是命令输出、「当前状态」轮换部分有没有被工作者覆盖、
  每个闸门是否逐条带 rc、关键决策点各项是否「无」得合理。
退出码：0 查的项都通过；3 有发现（逐条列出）；1 范围算不出（找不到 context.md、没有工作者条目、没有「## 当前状态」）；2 用法错误。
每次末尾印「查了 … 项」一行，说明查了哪些、哪些因 --no-git 等跳过。不输出「没有新东西」。
"""
import datetime
import re
import subprocess
import sys
from pathlib import Path

for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8")
    except (AttributeError, ValueError):
        pass

HDR = re.compile(r"^#{2,3} \[(\d{4}-\d\d-\d\d) (\d\d:\d\d)([^\]]*)\](.*)$")
ROLE = re.compile(r"工作者|全局者")
SHA = re.compile(r"提交[：:]\s*`?([0-9a-f]{7,40})`?")
NO_COMMIT = re.compile(r"提交[：:]\s*无[（(]")
KEYS = ["架构/接口变动", "安全相关", "偏离原计划", "未解决的疑虑"]


def label(name):
    return re.compile(r"\*\*\s*" + re.escape(name))


def parse_ts(date, hm):
    return datetime.datetime.strptime(f"{date} {hm}", "%Y-%m-%d %H:%M")


GITDIR = "."


def git(*args):
    # -C <context.md 所在目录>：传了别处的 context.md 时，H2/H7 查的是那个仓库，不是当前目录的仓库
    # 输出一律按 UTF-8 解码（Windows 的默认编码是 cp936，git status 里带中文的路径会抛错或乱码）
    r = subprocess.run(["git", "-C", GITDIR, "--no-optional-locks", *args], capture_output=True)
    r.stdout, r.stderr = r.stdout.decode("utf-8", "replace"), r.stderr.decode("utf-8", "replace")
    return r


def fence_mask(lines):
    """每行是否在代码围栏里（含围栏行本身）。``` 或 ~~~ 开头的行切换；围栏没闭合则到文末都算围栏里。"""
    mask, fence = [], None
    for l in lines:
        t = l.lstrip()
        if fence is None and (t.startswith("```") or t.startswith("~~~")):
            fence = t[:3]
            mask.append(True)
        elif fence is not None:
            mask.append(True)
            if t.startswith(fence):
                fence = None
        else:
            mask.append(False)
    return mask


def tz_offset(tz):
    """标题时区后缀 -> timedelta（相对 UTC）；没写后缀 -> None（按本机时间）；认不出 -> ValueError。"""
    t = tz.strip()
    if not t:
        return None
    if re.fullmatch(r"(UTC|GMT|Z)", t, re.I):
        return datetime.timedelta(0)
    m = re.fullmatch(r"(?:UTC|GMT)?\s*([+-])(\d{1,2})(?::?(\d\d))?", t, re.I)
    if not m:
        raise ValueError(t)
    d = datetime.timedelta(hours=int(m.group(2)), minutes=int(m.group(3) or 0))
    return d if m.group(1) == "+" else -d


def main(argv):
    path, no_git, fresh, now = "context.md", False, None, None
    i = 1
    pos = []
    while i < len(argv):
        a = argv[i]
        if a == "--no-git":
            no_git = True
        elif a == "--fresh" and i + 1 < len(argv):
            try:
                fresh = int(argv[i + 1])
            except ValueError:
                print(__doc__, file=sys.stderr)
                return 2
            i += 1
        elif a == "--now" and i + 1 < len(argv):
            try:
                now = datetime.datetime.strptime(argv[i + 1], "%Y-%m-%d %H:%M")
            except ValueError:
                print(__doc__, file=sys.stderr)
                return 2
            i += 1
        elif a.startswith("--"):
            print(__doc__, file=sys.stderr)
            return 2
        else:
            pos.append(a)
        i += 1
    if len(pos) > 1:
        print(__doc__, file=sys.stderr)
        return 2
    if pos:
        path = pos[0]
    global GITDIR
    p = Path(path)
    if not p.is_file():
        print(f"handoff-check：找不到 {path}，范围算不出", file=sys.stderr)
        return 1
    GITDIR = str(p.resolve().parent)
    lines = p.read_text(encoding="utf-8", errors="replace").split("\n")
    infence = fence_mask(lines)
    now = now or datetime.datetime.now().replace(second=0, microsecond=0)

    # 当前状态区段
    cs = [i for i, l in enumerate(lines) if not infence[i] and re.match(r"^## 当前状态", l)]
    if not cs:
        print("handoff-check：没有「## 当前状态」，范围算不出", file=sys.stderr)
        return 1
    cs_end = next((j for j in range(cs[0] + 1, len(lines)) if not infence[j] and lines[j].startswith("## ")), len(lines))
    cur_state = "\n".join(lines[cs[0]:cs_end])

    # 条目
    heads = []
    for i, l in enumerate(lines):
        m = HDR.match(l) if not infence[i] else None
        if m:
            r = ROLE.search(m.group(4))
            heads.append((i, m, r.group(0) if r else None))
    worker = [h for h in heads if h[2] == "工作者"]
    if not worker:
        print("handoff-check：context.md 里没有工作者条目（没有标题含「工作者」的 `## [时间]` 行），范围算不出", file=sys.stderr)
        return 1
    hi, hm, _ = worker[-1]
    nxt = next((j for j in range(hi + 1, len(lines)) if not infence[j] and (lines[j].startswith("## ") or HDR.match(lines[j]))), len(lines))
    block = "\n".join(lines[hi:nxt])
    findings, checked, skipped = [], [], []

    # H0
    checked.append("H0 最后一条工作者条目之后没有别的条目")
    fmt = "标题要写成 `## [YYYY-MM-DD HH:MM] 工作者 …`（中括号、两个或三个 #、含「工作者」）"
    later = [h for h in heads if h[0] > hi]
    ov = [h for h in later if h[2] == "全局者"]
    if ov:
        findings.append(f"H0 最后一条工作者条目（第 {hi + 1} 行，{hm.group(1)} {hm.group(2)}）之后已有全局者条目（第 {ov[0][0] + 1} 行）：这一轮没有新的工作者交接块，"
                        f"下面查的是上一轮的旧块。新块没写，或标题格式错了 —— {fmt}")
    norole = [h for h in later if h[2] is None]
    odd = [j for j in range(hi + 1, len(lines)) if not infence[j] and re.match(r"^#{1,6}\s*\[?\d{4}-\d\d-\d\d[ T]\d\d:\d\d", lines[j]) and not HDR.match(lines[j])]
    bad_titles = sorted([h[0] for h in norole] + odd)
    if bad_titles:
        findings.append(f"H0 最后一条工作者条目之后第 {bad_titles[0] + 1} 行有个像交接块的标题，但认不出是工作者条目：{lines[bad_titles[0]][:50]!r} —— {fmt}；"
                        "写错的话，下面查的是上一轮的旧块")

    # H1
    checked.append("H1 时间戳")
    try:
        ts = parse_ts(hm.group(1), hm.group(2))
        tz = hm.group(3).strip()
        ts_local = ts          # 与「现在」比的那个值（本机时间）
        vs_now = True
        try:
            off = tz_offset(tz)
            if off is not None:
                ts_local = ts - off + datetime.datetime.now().astimezone().utcoffset()
        except ValueError:
            vs_now = False
            skipped.append(f"H1 与现在比较（标题时区后缀「{tz}」认不出，不换算）")
        if vs_now and ts_local > now + datetime.timedelta(minutes=15):
            findings.append(f"H1 交接块时间 {ts:%Y-%m-%d %H:%M}{(' ' + tz) if tz else ''} 晚于现在（{now:%Y-%m-%d %H:%M}）超过 15 分钟：时间戳要先跑 date 取，不凭感觉")
        prev = [h for h in heads if h[0] < hi]
        if prev:
            pm = prev[-1][1]
            if pm.group(3).strip() == tz:
                pts = parse_ts(pm.group(1), pm.group(2))
                if ts < pts:
                    findings.append(f"H1 交接块时间 {ts:%Y-%m-%d %H:%M} 早于上一条条目 {pts:%Y-%m-%d %H:%M}")
        if vs_now and fresh is not None and now - ts_local > datetime.timedelta(minutes=fresh):
            findings.append(f"H1 交接块时间 {ts:%Y-%m-%d %H:%M}{(' ' + tz) if tz else ''} 距现在超过 {fresh} 分钟（--fresh）：这不是刚写的块，或时间戳不是跑 date 取的")
    except ValueError:
        findings.append(f"H1 标题里的时间戳解析不了：{lines[hi][:60]}")

    complete = bool(label("完成情况").search(block))
    if complete:
        # H2
        m = SHA.search(block)
        if m:
            sha = m.group(1)
            if no_git:
                skipped.append("H2 提交 sha 与祖先关系（--no-git）")
                checked.append("H2 提交行（只查格式）")
            else:
                checked.append("H2 提交行 + git 核对")
                t = git("cat-file", "-t", sha)
                if t.returncode != 0 or t.stdout.strip() != "commit":
                    findings.append(f"H2 提交 `{sha}` 不是这个仓库里的 commit（git cat-file -t 的结果：{t.stdout.strip() or t.stderr.strip()[:60]}）")
                elif git("merge-base", "--is-ancestor", sha, "HEAD").returncode != 0:
                    findings.append(f"H2 提交 `{sha}` 不是 HEAD 的祖先：下一轮安全预检会把它略过")
        elif NO_COMMIT.search(block):
            checked.append("H2 提交行（「提交：无（原因）」）")
        else:
            checked.append("H2 提交行")
            findings.append("H2 「完成情况」里没有「提交：`<sha>`」，也没有「提交：无（原因）」：先提交再交接")
        # H3
        checked.append("H3 完成阶段三个标签 + 四个关键词")
        for name in ("闸门结果", "spec 修正", "关键决策点"):
            if not label(name).search(block):
                findings.append(f"H3 完成阶段块缺「{name}」")
        k = label("关键决策点").search(block)
        if k:
            tail = block[k.start():]
            missing = [w for w in KEYS if w not in tail]
            if missing:
                findings.append("H3 「关键决策点」之后缺：" + "、".join(missing) + "（每项必须显式回答，无则写「无」）")
        # H4
        checked.append("H4 闸门结果里有 rc=")
        g = label("闸门结果").search(block)
        if g:
            gt = block[g.end():]
            # 只在已知的下一个标签处截断（不在任意粗体短语处截断：闸门输出和说明里常有粗体）
            stop = re.search(r"\n\*\*\s*(spec 修正|关键决策点|附带变动|完成情况)", gt)
            gt = gt[:stop.start()] if stop else gt
            first = gt.lstrip("：: *\n").split("\n", 1)[0].strip()
            if not re.match(r"无([（(。]|$)", first) and not re.search(r"rc\s*=\s*\d+", gt):   # 「无」「无。」「无（原因）」都算没有闸门
                findings.append("H4 「闸门结果」不是「无」，却一处 rc=<数字> 都没有：每条闸门要写退出码，不从输出推断")
    else:
        checked.append("H5 非完成阶段块的三个标签")
        for name in ("问题", "已尝试", "需要决策"):
            if not label(name).search(block):
                findings.append(f"H5 交接块（没有「完成情况」，按触发条件格式）缺「{name}」")

    # H6
    checked.append("H6 当前状态里的「未验证的前提」「backlog」")
    # 去掉 HTML 注释（可能跨行）后，只认行首标签：`**名字:**`、`**名字(括号):**`，或列表项 `- 名字:`；冒号半角全角都行。
    # 不能用子串：模板注释里本来就写着这两个词，正文里顺口提到也会误过
    state_body = re.sub(r"<!--.*?-->", "", cur_state, flags=re.S)
    for name in ("未验证的前提", "backlog"):
        entry = re.compile(r"^[ \t]*(?:[-*+][ \t]+)?(?:\*\*[ \t]*)?" + re.escape(name) + r"(?:[（(][^）)\n]*[）)])?\**[ \t]*[:：]", re.M)
        if not entry.search(state_body):
            findings.append(f"H6 「## 当前状态」里没有「{name}」这一行（没有就写「无」，省略不行）")

    # H7：只对完成阶段块查。触发切换（非完成阶段）时工作者常有未提交的半成品，查了只会误报
    if not complete:
        skipped.append("H7 工作树（非完成阶段块不查：切换时常有未提交的半成品）")
    elif no_git:
        skipped.append("H7 工作树未提交改动（--no-git）")
    else:
        st = git("status", "--porcelain")
        if st.returncode != 0:
            findings.append(f"H7 git status 失败：{st.stderr.strip()[:80]}")
            checked.append("H7 工作树")
        else:
            checked.append("H7 工作树")
            dirty = [l for l in st.stdout.splitlines() if l.strip()]
            dirty = [l for l in dirty if not re.search(r"(^|/)(context[^/]*\.md|sessions\.md)$", l[3:].strip().strip('"'))]
            if dirty:
                findings.append(f"H7 有 {len(dirty)} 个文件未提交（不含 context*.md、sessions.md）：" + "；".join(l.strip() for l in dirty[:5]) + ("…" if len(dirty) > 5 else ""))

    # H8
    checked.append("H8 交接块里没有 workflow-mode 行")
    for off, l in enumerate(block.split("\n")):
        if re.match(r"^\s*workflow[-_]mode\s*[:：]", l, re.I):
            findings.append(f"H8 交接块第 {off + 1} 行以 workflow-mode: 开头：整个 context.md 只许「当前状态」里有这一行，别处写成「模式：competition」，否则启动器会拒绝启动")
            break

    for f in findings:
        print(f"  ⚠ {f}")
    print(f"handoff-check：{path} 最后一条工作者条目在第 {hi + 1} 行（{hm.group(1)} {hm.group(2)}，{'完成阶段' if complete else '非完成阶段'}格式）；"
          f"查了 {len(checked)} 项（{'、'.join(checked)}）"
          + (f"；跳过 {len(skipped)} 项（{'、'.join(skipped)}）" if skipped else "") + f"；发现 {len(findings)} 项")
    return 3 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
