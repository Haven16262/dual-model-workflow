#!/usr/bin/env python3
"""context.md 体量：行数与字符数，同时给出排除「⚠️ 已证伪」墓碑后的口径。

用法: ctx-size.py <context.md>
字符数 = Unicode 字符数，不含换行（不用 wc -m：LC_ALL=C 下它数字节）。
墓碑 = 行级匹配 `- [ ]/[x] ⚠️ 已证伪`；WORKFLOW.md 规定墓碑不计入长度。
字符线（软线，只提醒不拦）：默认 DEFAULT_LINE；context.md 前 10 行里单独一行以「字符线：N」开头（全角或半角冒号，冒号后可有空白，N 为 ASCII 正整数，其后可跟空白+说明）可覆盖。比较用排除墓碑后的字符数。
退出码：0 正常（超线也是 0，靠输出里的「超线」提示）；1 墓碑格式认不出（含「已证伪」字样但一条墓碑也没识别到），
或前 10 行的「字符线」声明行不是恰好一条/取不出数字（范围算不出，不放行）；2 用法/读取错误。
"""
import re
import sys

DEFAULT_LINE = 30000
# 声明行：以「字符线」开头（可带引用块 `>`），冒号后是 ASCII 数字，之后只能是行尾或空白/括号开头的说明。
# 叙述句里中途出现的「字符线：N」不算声明，所以模板说明行不会触发。
DECL_START = re.compile(r"^\s*>?\s*字符线")
LINE_RE = re.compile(r"^\s*>?\s*字符线[：:]\s*([0-9]+)(?:\s.*|[（(].*)?$")
TOMB = re.compile(r"^\s*- (\[[ x]\] )?⚠️ ?\**已证伪")


def main(argv):
    # Windows 控制台默认 cp936，中文输出会乱码
    for s in (sys.stdout, sys.stderr):
        s.reconfigure(encoding="utf-8")
    if len(argv) != 2:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        with open(argv[1], encoding="utf-8") as f:
            lines = f.read().split("\n")
    except (OSError, UnicodeDecodeError) as e:
        print(f"读取失败: {e}", file=sys.stderr)
        return 2
    if lines and lines[-1] == "":
        lines.pop()  # 末尾换行不算一行

    tomb = [i for i, l in enumerate(lines, 1) if TOMB.match(l)]
    t_chars = sum(len(lines[i - 1]) for i in tomb)
    chars = sum(len(l) for l in lines)

    if not tomb and any("已证伪" in l for l in lines):
        print("含「已证伪」字样但没有识别到任何墓碑行，格式可能变了；不给出排除口径", file=sys.stderr)
        return 1

    line, src = DEFAULT_LINE, "默认"
    head = lines[:10]
    decl = [l for l in head if DECL_START.match(l)]
    if decl:
        ms = [LINE_RE.match(l) for l in decl]
        if len(decl) != 1 or not ms[0] or int(ms[0].group(1)) <= 0:
            print("前 10 行有「字符线」声明行，但不是恰好一条、或取不出正整数（如 5万、1,000），不给出线比较", file=sys.stderr)
            return 1
        line, src = int(ms[0].group(1)), "本项目覆盖"

    print(f"全部: {len(lines)} 行, {chars} 字符")
    print(f"排除墓碑后: {len(lines) - len(tomb)} 行, {chars - t_chars} 字符")
    if tomb:
        print(f"查了 {len(tomb)} 条墓碑，共 {t_chars} 字符，范围第 {tomb[0]}..{tomb[-1]} 行")
    else:
        print(f"查了 0 条墓碑（全文 {len(lines)} 行，无「已证伪」字样）")
    kept = chars - t_chars
    verdict = "超线" if kept > line else "未超线"
    print(f"字符线 {line}（{src}）：排除墓碑后 {kept} 字符 → {verdict}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
