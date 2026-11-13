#!/usr/bin/env python3
"""context.md「本 Phase 历史」里的悬空指针：指向会被覆盖或迁走的内容（WORKFLOW.md「撰写权限」）。

用法: ctx-pointers.py <context.md>
范围：context.md 里「## 本 Phase 历史」到文件末尾，整段都查（含第一条条目之前的说明）；
      context_history.md 不查（已归档的条目报了也没有对应动作）。
条目 = 以 `## ` 或 `### [` 开头的行（行首、行尾的完整注释先去掉再判；主标题和段落布局用同一套），只用来报条数和首末条。
**每一行都查，不靠解析决定跳过什么**：代码块、注释里的指针照样算命中、照样退出 3，只在命中后标「疑似在代码块/注释里」，
      由人判断是不是引用的示例。解析错位只会让标签错，不会漏报。
      （2026-10-19 语料数据：24 份里逐行全查与跳过代码块/注释的版本命中都是 78 处，落在代码块/注释里的 0 处；
      条目数、段落布局判定也全部相同 —— 跳过从没挡掉过误报，却三轮复审都被构造出假放行。）
标签的解析规则（只影响标签）：``` / ~~~ 围栏，列表项同一行开的算开头，闭合行不带列表前缀；反引号围栏的 info 里
      有反引号、波浪号围栏的 info 里有同长的 ~~~ 的，不算开头（「```pytest``` 通过」「~~~废弃方案~~~」）；
      行首开始的 HTML 注释，同一行接连的注释接着剥，注释后的同行内容不算围栏开头。
指针 = 「见/参见/详见 …当前状态」「见顶部」「见上一条/上一轮」—— 目标在别处、下一轮就不在了。
      「同上」「见上文」不算：多半指同一条目里的上一格/上一段，会跟着条目一起走。
      正则的增删以本机真实项目的 context.md 与归档为语料：只收语料里出现过的写法。语料清单（一行一份）
      与跑法见私有仓 scripts/tests/ctx_pointers_corpus.txt / ctx_pointers_corpus.sh（不导出），份数与各份退出码以其输出为准。
已知限制（语料里没出现过，没处理）：
      标签 —— 下面这些写法标签会错（该标没标或不该标却标了），命中和退出码不受影响：
             4 格以上缩进的围栏（顶层是缩进代码块，列表里才是围栏，没跟踪列表上下文）、
             列表项里开的注释（「- <!--」）、注释闭合后隔着文字再开的注释、`<!-->` 空注释、制表符缩进。
      布局 ——「## 当前状态」「## 跨 Phase 关键约定」出现在历史段后就退出 1，在代码块里引用也算（宁可报错不放行）。
      漏报 ——「见上轮」「见上节」「见「上一条」」「参考/同 当前状态」、「见」与「当前状态」隔 17 字及以上；
             指针被硬换行拆在两行（逐行匹配）；
             「见上方…」不报：语料里既有指本条目上文、也有指早先条目、也有指当前状态的，分不开。
      误报 ——「足见/预见 当前状态」、「见订单当前状态字段」、行内代码 `见当前状态` 里的引用。
退出码：0 没有命中（标题之后每一行都查过）；3 有命中（逐条列出，含疑似在代码块/注释里的）；
        1 范围算不出（该标题不是恰好 1 个、有行像该标题又不完全一致、或段后又出现另两块的标题）；2 用法/读取错误。
"""
import re
import sys

SECTION = "## 本 Phase 历史"
OTHER = ("## 当前状态", "## 跨 Phase 关键约定")
# 「见」前排除 意见/常见/可见/没见…；间隔不跨句读和逗号冒号；「当前状态机」不算
POINTER = re.compile(r"(?<![意常可没未看遇听罕])见(?:[^。；，,：:\n]{0,16}当前状态(?!机)|顶部|上一条|上一轮)")
FENCE_OPEN = re.compile(r"^[ \t]*(?:(?:[-*+]|\d+[.)])[ \t]+)?(`{3,}|~{3,})(.*)")
FENCE_CLOSE = re.compile(r"^[ \t]*(`{3,}|~{3,})[ \t]*$")
# 注释体用「不含 -->」的写法，不用 .*?：相邻多段注释时 .*? 会指数级回溯
# 像该标题的行（任意缩进、空白、标题里夹注释）：二级标题文字以「本 Phase 历史」开头，或任意级标题文字恰为它，或 setext 标题。
# 其他级别、文字更长的（如语料里真有的「### 本 Phase 历史原文」）是别的小节，不算
_CMTS = r"\s*(?:<!--(?:(?!-->).)*-->\s*)*"
NEAR = re.compile(r"^\s*(?:##(?!#)" + _CMTS + r"本\s*Phase\s*历史|#{1,6}" + _CMTS + r"本\s*Phase\s*历史\s*#*\s*$)")
SETEXT_TEXT = re.compile(r"\s*本\s*Phase\s*历史\s*")
SETEXT_LINE = re.compile(r"^ {0,3}(?:=+|-+)[ \t]*$")
LEAD_CMT = re.compile(r"^[ \t]*(?:<!--(?:(?!-->).)*-->[ \t]*)+")
ENTRY = re.compile(r"^(?:## |### \[)")
STAMP = re.compile(r"^#{2,3} \[(\d{4}-\d{2}-\d{2} \d{2}:\d{2})")


def bare(l):
    """去掉行首、行尾的完整注释，用来认标题（主标题与段落布局、条目同一套）。"""
    l = LEAD_CMT.sub("", l).rstrip()
    while l.endswith("-->"):  # 行尾注释从后往前逐段剥；不用行尾锚定的正则，长行上会退化成平方
        j = l.rfind("<!--")
        if j < 0 or "-->" in l[j + 4:-3]:
            break
        l = l[:j].rstrip()
    return l


def in_blocks(lines, start):
    """疑似在代码块/注释里的行号（0 起）。只用来给命中打标签，不决定查不查。"""
    out = set()
    fence = None
    comment = False
    for i in range(start, len(lines)):
        l = lines[i]
        if fence:  # 闭合行只能是同种符号、不短于开头、后面没有别的字、不带列表前缀
            m = FENCE_CLOSE.match(l)
            if m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence):
                fence = None
            out.add(i)
            continue
        stripped = False  # 这一行剥过注释
        if comment:
            if "-->" not in l:
                out.add(i)
                continue
            comment, l, stripped = False, l.split("-->", 1)[1], True
        # 只认行首开始的注释（正文里引用的 `<!--` 不算）；闭合后同行紧跟的注释接着剥
        while l.lstrip(" \t").startswith("<!--"):
            rest = l.split("<!--", 1)[1]
            if "-->" not in rest:
                comment = True
                break
            l, stripped = rest.split("-->", 1)[1], True
        if comment:
            out.add(i)
        elif not stripped:  # 注释后的同行内容不开代码块
            m = FENCE_OPEN.match(l)
            if m and (m.group(1)[0] if m.group(1)[0] == "`" else m.group(1)) not in m.group(2):
                fence = m.group(1)
                out.add(i)
    return out


def main(argv):
    # Windows 控制台默认 cp936，中文输出会乱码
    for s in (sys.stdout, sys.stderr):
        s.reconfigure(encoding="utf-8")
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        with open(argv[1], encoding="utf-8") as f:
            lines = f.read().replace("\r\n", "\n").split("\n")
    except (OSError, UnicodeDecodeError) as e:
        print(f"读取失败: {e}", file=sys.stderr)
        return 2

    starts, near = [], []
    for i, l in enumerate(lines):
        h = bare(l)
        if h == SECTION:
            starts.append(i)
        elif NEAR.match(h) or (SETEXT_TEXT.fullmatch(h) and i + 1 < len(lines) and SETEXT_LINE.match(lines[i + 1])):
            near.append((i, h))
    if near:  # 像主标题又不完全是（后跟文字、没闭合的注释）：认不准起点，不猜
        i, h = near[0]
        print(f"第 {i + 1} 行「{h[:40]}」像「{SECTION}」标题又不完全一致，起点认不准，范围算不出", file=sys.stderr)
        return 1
    # 代码块里的同名行也算：起点有歧义就退出 1
    if len(starts) != 1:
        print(f"「{SECTION}」标题有 {len(starts)} 个（应为 1 个），范围算不出", file=sys.stderr)
        return 1

    blocks = in_blocks(lines, starts[0] + 1)
    entries, hits = [], []  # entries: (行号, 标题)；hits: (行号, 指针, 原文, 疑似在代码块/注释里)
    for i in range(starts[0] + 1, len(lines)):  # 每一行都查，解析结果只用来打标签
        l, no = lines[i], i + 1
        head = bare(l)
        if ENTRY.match(head):
            if head in OTHER:
                print(f"第 {no} 行在「{SECTION}」之后又出现「{head}」，段落布局认不出", file=sys.stderr)
                return 1
            entries.append((no, head))
        for p in POINTER.finditer(l):
            hits.append((no, p.group(0), l.strip(), i in blocks))

    if entries:
        def label(e):
            s = STAMP.match(e[1])
            return s.group(1) if s else f"第 {e[0]} 行「{e[1].lstrip('#').strip()[:20]}」"
        first = f"，首末条 {label(entries[0])}..{label(entries[-1])}"
    else:
        first = ""
    end = len(lines) - (lines[-1] == "")
    inside = sum(h[3] for h in hits)
    print(f"查了第 {starts[0] + 1}..{end} 行（「{SECTION}」整段逐行全查，{len(entries)} 条条目{first}）；悬空指针 {len(hits)} 处，其中疑似在代码块/注释里 {inside} 处")
    for no, what, text, blk in hits:
        print(f"  第 {no} 行「{what}」{'（疑似在代码块/注释里）' if blk else ''}：{text[:80]}")
    return 3 if hits else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
