#!/usr/bin/env python3
"""sessions.md：本项目开过的会话，一行一个 sessionId。由全局者 / 工作者在交接时运行（WORKFLOW.md「切换触发条件」）。

用法: sessions-md.py <项目目录> [--note "做了什么"] [--sid <sessionId> [--backfill]] [--dry-run | --out <路径>]
  --note    只写「做了什么」列，只写自己那一行（自己 = 环境变量 CLAUDE_CODE_SESSION_ID；没有这个变量时用 --sid 指定，
            此时脚本认不出「自己」，stderr 印警告，也就拦不住写别人那一行 —— 这是降级，不是权限边界）。
            覆盖自己那一行原有的备注：每次交接写到目前为止的累计一句，最后一次交接写的就是终稿。
  --sid X --backfill
            给别的会话补记（典型：前任崩了没写）。只许写「做了什么」为空的行，写进去带「补记（<自己 sid 前 8 位>）：」前缀。
  --dry-run 不加锁、不写文件，把生成结果打到 stdout。
  --out     写到指定路径而不是 <项目目录>/sessions.md（演练用；仍读 <项目目录>/sessions.md 里已有的备注）。

机械列（除「做了什么」外全部）每次从来源重算，再与文件里已有的那一行合并：开始取早、末次取晚、model/effort 取并集，
      SessionEnd 有一次就算有。来源里已经查不到的会话（遥测归档被删、transcript 过期、另一台机器开的）整行原样保留，
      所以这份文件只增不减，来源变少不会让它变少。
来源（按存在与否降级，缺哪个在摘要里写明）：
  1. transcript：~/.claude/projects/<项目目录 slug>/*.jsonl（CC 自带，各机器都有）—— 会话名（custom-title）、
     model、effort、起止时间、入口（交互 / -p）。
  2. manager 遥测：~/.claude/manager/telemetry/status-events.ndjson{,.1} + archive/status-events.ndjson.*.gz
     —— 只认 workspace.project_dir 等于项目目录的行（不认 cwd：别处启动、中途 cd 进来的会话 cwd 也会等于项目目录）；
     events.ndjson{,.1} + archive/events.ndjson.*.gz 只取上面这些 sessionId 的 SessionEnd。
     没装 manager 的机器没有这个目录：SessionEnd 列写「未知」，其余字段只靠 transcript。
自检：真写 sessions.md 时（不是 --dry-run / --out），运行它的会话自己必须出现在来源里，否则退出 1 ——
      多半是没从项目目录启动，或这台机器的 transcript 目录 slug 规则和这里不一样。
「接替自谁」不在机械列里：同角色会话时间重叠时只在「重叠」列标出对方，不推断谁接谁。
退出码：0 已写（或 --dry-run 已打印）；1 拒绝（已有文件解析不了、--note 的会话在来源和文件里都没有、
        --sid 不是自己却没带 --backfill 或那一行已有备注、自检看不到自己、拿不到锁、
        最终 0 行 —— 来源里没有本项目的会话、文件也不存在或是空表，范围算不出就不写）；2 用法错误。
摘要行无条件印「已结束但『做了什么』为空的角色会话 N 行」和其中最近的至多 5 个（sid 前 8 位 + 会话名）：
        这是给继任者看的趋势数字，不是告警；存量项目落地时的 N 是基线，看它是否只降不升。
"""
import glob
import gzip
import json
import os
import re
import socket
import subprocess
import sys
import tempfile
import time
from datetime import datetime

TELEMETRY = os.path.expanduser("~/.claude/manager/telemetry")
PROJECTS = os.path.expanduser("~/.claude/projects")
COLS = ["起 (UTC)", "止 (UTC)", "机器", "角色", "会话名", "model", "effort",
        "SessionEnd", "transcript", "重叠", "sessionId", "做了什么"]
NOTE = "做了什么"
ROLE_RE = re.compile(r"-(overseer|worker)-")
ROLE_ZH = {"overseer": "全局者", "worker": "工作者"}
OVERLAP_MIN = 10  # 交班时新会话先开、旧会话后关，1–2 分钟的交叠是正常接力，不标
HEADER = """# sessions.md — 本项目开过的会话

> 由 `sessions-md.py` 生成，一行一个 sessionId，按开始时间排序。**除「做了什么」外都是机械列，手改会被下次运行覆盖**；
> 「做了什么」只写自己那一行：`python3 ~/.claude/scripts/sessions-md.py . --note "…"`。
> resume：在项目目录下跑 `claude --resume <sessionId>`；transcript 列为「已删」的 resume 不了。
> 「止」：SessionEnd 为 ✓ 时是进程退出时刻（可能比最后一条消息晚很久：空闲挂着、最后被 kill）；否则是最后一次看得到的活动。
> 「重叠」= 同角色会话时间有交叠，这几行的先后不能当作接替关系。角色启动时不必读这份文件。
"""


def iso(ts):
    return ts[:16].replace("T", " ") if ts else ""


def machine_tag():
    try:
        with open(os.path.expanduser("~/.claude/machine-tag"), encoding="utf-8") as f:
            tag = re.sub(r"[^A-Za-z0-9]", "", f.read())
    except OSError:
        tag = ""
    return tag or socket.gethostname()


def slug(path):
    return re.sub(r"[^A-Za-z0-9]", "-", path)


def new_rec():
    return {"start": "", "end": "", "names": [], "models": [], "efforts": [],
            "ended": False, "entry": "", "prompt": "", "transcript": ""}


def touch(rec, ts):
    if ts:
        if not rec["start"] or ts < rec["start"]:
            rec["start"] = ts
        if ts > rec["end"]:
            rec["end"] = ts


def base(v):
    return re.sub(r"\[[^\]]*\]$", "", v)  # 遥测写 deepseek-flash[1m]，transcript 写 deepseek-flash


def add(lst, v):
    # <synthetic> 是 CC 自己插的消息（报错、压缩），不是模型
    if v and v != "<synthetic>" and base(v) not in map(base, lst):
        lst.append(v)


def norm_ts(ts):
    # transcript 用 2026-10-10T06:30:03.929Z，遥测用 2026-10-10T06:30:03Z；统一成秒级 Z
    return ts[:19] + "Z" if ts and len(ts) >= 19 else ""


def open_any(path):
    return gzip.open(path, "rt", encoding="utf-8", errors="replace") if path.endswith(".gz") \
        else open(path, encoding="utf-8", errors="replace")


def tele_files(stem):
    arch = sorted(glob.glob(os.path.join(TELEMETRY, "archive", stem + ".*.gz")))
    live = [os.path.join(TELEMETRY, stem + s) for s in (".1", "")]
    return arch + [p for p in live if os.path.exists(p)]


def read_telemetry(root, recs, stats):
    if not os.path.isdir(TELEMETRY):
        stats["telemetry"] = "不存在（未装 manager）"
        return False
    needle = json.dumps(root)[1:-1]  # 先做子串过滤，命中再 json.loads
    files = tele_files("status-events.ndjson")
    n, lo, hi = 0, "", ""
    for p in files:
        with open_any(p) as f:
            for line in f:
                n += 1
                if needle not in line:
                    continue
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                ts = d.get("_captured_at", "")
                lo = min(lo, ts) if lo else ts
                hi = max(hi, ts)
                if (d.get("workspace") or {}).get("project_dir") != root:
                    continue
                sid = d.get("session_id")
                if not sid:
                    continue
                r = recs.setdefault(sid, new_rec())
                touch(r, norm_ts(ts))
                add(r["names"], d.get("session_name"))
                add(r["models"], (d.get("model") or {}).get("id"))
                add(r["efforts"], (d.get("effort") or {}).get("level"))
                if not r["entry"]:
                    r["entry"] = "交互"  # 有 statusline 就是交互会话
                if d.get("transcript_path") and not r["transcript"]:
                    r["transcript"] = d["transcript_path"]
    span = f"含本项目路径的行 {lo[:16]}..{hi[:16]}" if lo else "含本项目路径的行 0 行"
    stats["telemetry"] = f"status {len(files)} 份 {n} 行（{span}）"
    return True


def read_session_ends(recs, stats):
    """必须在 transcript 之后跑：-p 会话（K10 第三者）没有 statusline，只在 transcript 里出现。"""
    efiles = tele_files("events.ndjson")
    m, elo = 0, ""
    for p in efiles:
        with open_any(p) as f:
            for line in f:
                m += 1
                if not elo:
                    try:
                        elo = norm_ts(json.loads(line).get("_captured_at", ""))
                    except ValueError:
                        pass
                if '"SessionEnd"' not in line:
                    continue
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                r = recs.get(d.get("session_id"))
                if r is not None and d.get("hook_event_name") == "SessionEnd":
                    r["ended"] = True
                    touch(r, norm_ts(d.get("_captured_at", "")))
    stats["telemetry"] += f"，events {len(efiles)} 份 {m} 行（{'自 ' + elo[:16] if elo else '0 行'}）"
    stats["events_from"] = elo


TITLE_RE = re.compile(r'"customTitle":"((?:[^"\\]|\\.)*)"')


def read_transcript(path, recs, sid_hint=None):
    """逐行读；只对含所需键的行 json.loads。返回 sessionId，读不了返回 None。"""
    sid = sid_hint
    r, titles = None, []
    try:
        f = open(path, encoding="utf-8", errors="replace")
    except OSError:
        return None
    with f:
        for line in f:
            if '"type":"custom-title"' in line:
                mt = TITLE_RE.search(line)
                if mt:
                    add(titles, json.loads('"' + mt.group(1) + '"'))
                continue
            if '"timestamp"' not in line or '"sessionId"' not in line:
                continue
            try:
                d = json.loads(line)
            except ValueError:
                continue
            if d.get("isSidechain"):
                continue
            sid = sid or d.get("sessionId")
            if not sid:
                continue
            if r is None:
                r = recs.setdefault(sid, new_rec())
            touch(r, norm_ts(d.get("timestamp", "")))
            if not r["entry"] and d.get("entrypoint"):
                r["entry"] = "-p" if d["entrypoint"].startswith("sdk") else "交互"
            if d.get("type") == "assistant":
                add(r["models"], (d.get("message") or {}).get("model"))
                add(r["efforts"], d.get("effort"))
            elif d.get("type") == "user" and not r["prompt"]:
                c = (d.get("message") or {}).get("content")
                if isinstance(c, str):
                    r["prompt"] = c.strip().split("\n", 1)[0][:24]
    if r is None:
        return None  # 没有一行带时间戳：不算一个会话（否则会生成起止为空的行）
    for t in titles:
        add(r["names"], t)
    r["transcript"] = path
    return sid


def read_transcripts(root, recs, stats):
    d = os.path.join(PROJECTS, slug(root))
    paths = set(glob.glob(os.path.join(d, "*.jsonl")))
    # 遥测里登记过、但不在 slug 目录下的 transcript（启动目录与项目目录写法不同时）
    paths |= {r["transcript"] for r in recs.values() if r["transcript"] and os.path.exists(r["transcript"])}
    got = sum(1 for p in sorted(paths) if read_transcript(p, recs, os.path.basename(p)[:-6]))
    stats["transcript"] = f"{len(paths)} 个，读出会话 {got} 个（{d}{'' if os.path.isdir(d) else '，目录不存在'}）"
    return got > 0


# ---------- sessions.md 读写 ----------

def split_row(line):
    """格内只有一种转义：`\\|` 读成 `|`；别的反斜杠原样保留（路径里的 `C:\\x` 不受影响）。与 cell() 互逆。"""
    cells, buf, body, i = [], "", line.strip()[1:], 0
    while i < len(body):
        ch = body[i]
        if ch == "\\" and body[i + 1:i + 2] == "|":
            buf += "|"
            i += 2
            continue
        if ch == "|":
            cells.append(buf.strip())
            buf = ""
        else:
            buf += ch
        i += 1
    return cells


def cell(s):
    s = str(s).replace("\n", " ").replace("|", "\\|")
    # 以反斜杠结尾时补一个空格，否则它会和后面的分隔符拼成 `\\|`；读回时 strip() 去掉
    return s + " " if s.endswith("\\") else s


def parse_existing(path):
    """返回 {sid: {列名: 值}}；文件不存在返回 {}；解析不了抛 ValueError（不覆盖人写的备注）。"""
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as f:
        lines = f.read().split("\n")
    table = [l for l in lines if l.lstrip().startswith("|")]
    if not table:
        raise ValueError("文件存在但没有表格")
    head = split_row(table[0])
    if "sessionId" not in head or NOTE not in head:
        raise ValueError(f"表头缺 sessionId 或 {NOTE} 列：{head}")
    rows = {}
    for i, l in enumerate(table[2:], 3):
        c = split_row(l)
        if len(c) != len(head):
            raise ValueError(f"表格第 {i} 行有 {len(c)} 格，表头 {len(head)} 格")
        row = dict(zip(head, c))
        rows[row["sessionId"]] = row
    return rows


def render_row(sid, r, tag):
    names = r["names"]
    name = " → ".join(names) if names else f"（无名{'，-p' if r['entry'] == '-p' else ''}）{r['prompt']}"
    m = ROLE_RE.search(names[-1]) if names else None
    role = ROLE_ZH[m.group(1)] if m else ("-p" if r["entry"] == "-p" else "其他")
    if r["ended"]:
        end = "✓"
    else:
        end = "无" if r.get("tele") else "未知"
    tr = "✓" if r["transcript"] and os.path.exists(r["transcript"]) else "已删"
    return {"起 (UTC)": iso(r["start"]), "止 (UTC)": iso(r["end"]), "机器": tag, "角色": role,
            "会话名": name, "model": " → ".join(r["models"]), "effort": " → ".join(r["efforts"]),
            "SessionEnd": end, "transcript": tr, "重叠": "", "sessionId": sid, NOTE: ""}


def merge(old, new):
    out = dict(new)
    for k in ("机器", "角色"):
        out[k] = old.get(k) or new[k]
    starts = [x for x in (old.get("起 (UTC)"), new["起 (UTC)"]) if x]
    out["起 (UTC)"] = min(starts) if starts else ""
    out["止 (UTC)"] = max(old.get("止 (UTC)", ""), new["止 (UTC)"])
    for k in ("会话名", "model", "effort"):
        seq = [v for v in old.get(k, "").split(" → ") if v]
        for v in new[k].split(" → "):
            add(seq, v)
        out[k] = " → ".join(seq) or new[k]
    if old.get("SessionEnd") == "✓":
        out["SessionEnd"] = "✓"
    out[NOTE] = old.get(NOTE, "")
    return out


def minutes(a, b):
    fmt = "%Y-%m-%d %H:%M"
    return (datetime.strptime(b, fmt) - datetime.strptime(a, fmt)).total_seconds() / 60


def mark_overlap(rows):
    by_role = {}
    for r in rows:
        if r["角色"] in ("全局者", "工作者"):
            by_role.setdefault((r["机器"], r["角色"]), []).append(r)
    for group in by_role.values():
        group = [r for r in group if r["起 (UTC)"] and r["止 (UTC)"]]  # 手改或旧行可能缺时间
        for a in group:
            hits = [b["sessionId"][:8] for b in group if b is not a and minutes(
                max(a["起 (UTC)"], b["起 (UTC)"]), min(a["止 (UTC)"], b["止 (UTC)"])) > OVERLAP_MIN]
            a["重叠"] = " ".join(hits)


def lock_path(root):
    try:
        gd = subprocess.run(["git", "-C", root, "rev-parse", "--absolute-git-dir"],
                            capture_output=True, text=True, timeout=10).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        gd = ""
    base = gd if gd and os.path.isdir(gd) else root
    return os.path.join(base, "sessions-md-" + slug(root)[-60:] + ".lock")


def acquire(lp, wait=30):
    """内核文件锁：持锁进程无论怎么死（含 SIGKILL），锁都随文件描述符释放，没有「残留锁」要判断和清理。
    锁文件本身留着（空文件，在 .git 里），不删 —— 删锁文件正是竞态的来源。返回打开的文件对象，拿不到返回 None。"""
    f = open(lp, "a+")
    t0 = time.time()
    while True:
        try:
            if os.name == "nt":
                import msvcrt
                f.seek(0)
                msvcrt.locking(f.fileno(), msvcrt.LK_NBLCK, 1)
            else:
                import fcntl
                fcntl.flock(f.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
            return f
        except OSError:
            if time.time() - t0 > wait:
                f.close()
                return None
            time.sleep(0.2)


def write_atomic(path, text):
    d = os.path.dirname(os.path.abspath(path))
    fd, tmp = tempfile.mkstemp(prefix=".sessions-md-", suffix=".tmp", dir=d)
    # mkstemp 建出来是 0600，os.replace 会把它带给 sessions.md；改回按 umask 的普通文件权限（通常 0644）
    mask = os.umask(0)
    os.umask(mask)
    try:
        os.chmod(tmp, 0o666 & ~mask)
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, path)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def main(argv):
    for s in (sys.stdout, sys.stderr):
        s.reconfigure(encoding="utf-8")
    args, opts = [], {}
    it = iter(argv[1:])
    for a in it:
        if a in ("--note", "--sid", "--out"):
            opts[a] = next(it, None)
            if opts[a] is None:
                print(__doc__, file=sys.stderr)
                return 2
        elif a in ("--dry-run", "--backfill"):
            opts[a] = True
        else:
            args.append(a)
    if len(args) != 1 or ("--dry-run" in opts and "--out" in opts) or ("--backfill" in opts and "--sid" not in opts):
        print(__doc__, file=sys.stderr)
        return 2
    root = os.path.realpath(args[0])
    target = os.path.join(root, "sessions.md")
    out_path = opts.get("--out") or target

    recs, stats = {}, {}
    has_tele = read_telemetry(root, recs, stats)
    read_transcripts(root, recs, stats)
    if has_tele:
        read_session_ends(recs, stats)
    # SessionEnd 写「无」只在 events 覆盖了这个会话的开始时刻时；否则没记到不等于没发生，写「未知」
    elo = stats.get("events_from", "")
    for r in recs.values():
        r["tele"] = bool(elo) and r["start"] >= elo

    lp = lock = None
    if "--dry-run" not in opts and "--out" not in opts:
        lp = lock_path(root)
        lock = acquire(lp)
        if lock is None:
            print(f"拿不到锁 {lp}：另一个进程持锁超过 30 秒", file=sys.stderr)
            return 1
    try:
        try:
            old = parse_existing(target)
        except ValueError as e:
            print(f"{target} 解析不了，拒绝覆盖（里面有人写的备注）：{e}", file=sys.stderr)
            return 1
        me = os.environ.get("CLAUDE_CODE_SESSION_ID")
        if not me:
            print("警告：没有环境变量 CLAUDE_CODE_SESSION_ID，认不出「自己」：自检跳过，--sid 写哪一行都不拦", file=sys.stderr)
        if lp and me and me not in recs:
            print(f"自检：运行本脚本的会话 {me[:8]} 不在来源里（没从项目目录启动？transcript 目录 slug 不对？），没写",
                  file=sys.stderr)
            return 1
        tag = machine_tag()
        rows, added, updated = {}, 0, 0
        for sid, r in recs.items():
            new = render_row(sid, r, tag)
            if sid in old:
                rows[sid] = merge(old[sid], new)
                updated += 1
            else:
                rows[sid] = new
                added += 1
        kept = 0
        for sid, row in old.items():
            if sid not in rows:
                rows[sid] = {c: row.get(c, "") for c in COLS}
                kept += 1
        note_sid = None
        if "--note" in opts:
            note_sid = opts.get("--sid") or me
            if not note_sid or note_sid not in rows:
                print(f"--note：会话 {note_sid or '（没有 --sid，也没有 CLAUDE_CODE_SESSION_ID）'} "
                      f"在来源和文件里都找不到，没写", file=sys.stderr)
                return 1
            note = opts["--note"].replace("\n", " ").strip()
            if me and note_sid != me:
                if "--backfill" not in opts or rows[note_sid][NOTE]:
                    print(f"--note：{note_sid[:8]} 不是自己（{me[:8]}）；补记别人要带 --backfill，且只写备注为空的行，没写",
                          file=sys.stderr)
                    return 1
                note = f"补记（{me[:8]}）：{note}"
            rows[note_sid][NOTE] = note
        if not rows:
            print(f"本项目 0 个会话（transcript {stats['transcript']}；遥测 {stats['telemetry']}），"
                  f"{target} 也不存在或是空表：范围算不出，没写。项目目录写对了吗？", file=sys.stderr)
            return 1
        ordered = sorted(rows.values(), key=lambda x: (x["起 (UTC)"], x["sessionId"]))
        mark_overlap(ordered)

        # 文件里不写生成时间、来源统计：每次都变的行会让两台机器各跑一次就必然 git 冲突。统计只进摘要
        body = [HEADER, "| " + " | ".join(COLS) + " |", "|" + "---|" * len(COLS)]
        for r in ordered:
            body.append("| " + " | ".join(cell(r[c]) for c in COLS) + " |")
        text = "\n".join(body) + "\n"

        # 「已结束但「做了什么」为空的角色会话 N 行」这句是对外契约：/as-overseer 第 2 步按
        # `grep -o '为空的角色会话 [0-9]* 行'` 取 N，改措辞要同步改那里（测试 overseer_grep 守着）
        empty = [r for r in ordered if r["角色"] in ("全局者", "工作者") and r["SessionEnd"] == "✓" and not r[NOTE]]
        recent = "、".join(f"{r['sessionId'][:8]} {r['会话名']}" for r in reversed(empty[-5:]))
        summary = (f"[sessions-md] 查了 transcript {stats['transcript']}；遥测 {stats['telemetry']}。"
                   f"本项目会话 {len(ordered)} 行：新增 {added}，按来源更新 {updated}，来源已查不到、原样保留 {kept}"
                   + (f"；备注写入 {note_sid[:8]}" if note_sid else "")
                   + f"；已结束但「做了什么」为空的角色会话 {len(empty)} 行"
                   + (f"（最近的：{recent}；前任的可按前 8 位在 sessions.md 里查完整 sid，用 --sid <完整 sid> --backfill 补记）" if empty else ""))
        if "--dry-run" in opts:
            sys.stdout.write(text)
            print(summary, file=sys.stderr)
            return 0
        write_atomic(out_path, text)
        print(summary + f" → {out_path}")
        return 0
    finally:
        if lock:
            lock.close()  # 关闭描述符即释放锁


if __name__ == "__main__":
    sys.exit(main(sys.argv))
