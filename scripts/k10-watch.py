#!/usr/bin/env python3
"""k10-watch — K9 值班：按日历和 K9 判据召唤第三者，不经过全局者。

WORKFLOW.md「工作模式与旋钮表」K9、K10 两行的机械部分。由 cron 定时跑，每个项目一行：
    */30 * * * * flock -n /tmp/k10-<proj>.lock ~/.claude/scripts/k10-watch.py <project-dir> >> <log> 2>&1

每轮（全部确定性判定，零 LLM；只有触发时才调模型）：
  1. 读模式行（调用 dual-model-mode.sh，规则只有一份）。没有模式行 → 不判定，但输出一行说明。
  2. 读 `.workflow/k10.json`（开工确认时写入，改动需用户同意）。
  3. 判定三类触发：
     - calendar：日历条目的日期 ≤ 今天（UTC），且还没触发过；
     - k9_position：外部位置。最好分 < 「提交次数 ≤ ext_k 的队伍」的分数中位数，或者这些队伍里
       高于我们的队数 ≥ ext_count_above。边沿触发：触发一次后，要等条件解除再重新布防；
     - k9_day2：到 day2_date 后，最好分 < 截线 × (1 − day2_cutline_pct%)，只触发一次；
     - k9_stall：停滞。已读出分数的包比上次判定多了至少 N 个时才判：
       近 N 包增量 ÷ N × 剩余名额 < 距目标差（有排行榜时；剩余名额只算今天之后的天数）；
       没有排行榜时，用近 N 包合计增量 < fixed_X。
  4. 触发先按（触发, 角色）入队并落盘，再逐个启动第三者（`claude -p`）。成功的报告原样写进
     `.workflow/reports/`；失败的记录写进 `.workflow/k10-failures/`（不进 reports，免得 Stop 钩子
     要求回应一份失败记录），下一轮重试，累计 MAX_ATTEMPTS 次仍失败就放弃并记日志。
     有新报告时发门铃（一个只放行 ListAgents / SendMessage 的 `claude -p`），通知全局者。
  5. 状态写进 `.workflow/k10-state.json`（本脚本独占），每一步之后都落盘，崩溃也不会重复召唤。
  日历和 K9 分开判定：K9 算不出（抛错）时，日历照常处理，退出码记为 2。

输出：每轮都打印「查了 N 个触发条件（…），触发 M 个」；不会输出「没有新东西」。
退出码：0 正常；1 有第三者或门铃失败（已记日志）；2 输入不全，范围算不出（例如缺 k10.json）。
"""
import copy
import json
import os
import shutil
import statistics
import subprocess
import sys
import tempfile
from datetime import date, datetime, timezone
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent
MODE_SCRIPT = Path(os.environ.get("K10_MODE_SCRIPT", SCRIPTS / "dual-model-mode.sh"))
CLAUDE = os.environ.get("K10_CLAUDE", "claude")
RO_TOOLS = "Read,Grep,Glob,WebSearch,WebFetch"
MAX_ATTEMPTS = 2


def today():
    s = os.environ.get("K10_TODAY")  # 测试用
    return date.fromisoformat(s) if s else datetime.now(timezone.utc).date()


def log(msg):
    print(f"[k10-watch {datetime.now(timezone.utc):%Y-%m-%d %H:%M}Z] {msg}", flush=True)


def read_mode(proj):
    p = subprocess.run([str(MODE_SCRIPT), "mode", str(proj / "context.md")], capture_output=True, text=True)
    if p.returncode != 0:
        raise ValueError("模式行非法：" + p.stderr.strip())
    return p.stdout.strip()


def read_tsv(path):
    if not path.exists():
        return None
    lines = [l.rstrip("\r\n") for l in path.read_text(encoding="utf-8").splitlines() if l.strip()]
    if not lines:
        return []
    head = lines[0].split("\t")
    return [dict(zip(head, l.split("\t"))) for l in lines[1:]]


def best_series(scores):
    """按行序（上传顺序）返回「当前最好分」序列。"""
    out, best = [], None
    for r in scores:
        v = float(r["score"])
        best = v if best is None else max(best, v)
        out.append(best)
    return out


def judge_calendar(cfg, state):
    """日历判定。和 K9 分开算：K9 出错不能连累日历（verifier 第十轮 D）。"""
    checked, triggers = [], []
    t = today()
    for c in cfg.get("calendar", []):
        checked.append(f"calendar:{c['id']}")
        if date.fromisoformat(c["date"]) <= t and c["id"] not in state["calendar_fired"]:
            triggers.append({"kind": "calendar", "id": c["id"], "roles": c["roles"],
                             "reason": f"日历召唤 {c['id']}（{c['date']}）"})
    return checked, triggers


def judge_k9(cfg, state, scores, board):
    """K9 判定：外部位置（中位数 / 高于我们的队数 / 第 2 天对截线）+ 停滞。算不出时抛 ValueError。"""
    checked, triggers = [], []
    k9 = cfg.get("k9")
    if not k9 or scores is None:
        return checked, triggers
    t = today()
    series = best_series(scores)
    best = series[-1] if series else None
    roles = k9.get("roles", ["skeptic", "proposer"])
    cutline = None
    if board:
        ranked = sorted(board, key=lambda r: int(r["rank"]))
        tr = k9.get("target_rank", 10)
        if len(ranked) >= tr:
            cutline = float(ranked[tr - 1]["score"])
    # ① 外部位置。中位数对 ext_k 很敏感（一次比赛回放里，k=1/3/5 时中位数差了 25 分），
    #    所以再加「低提交队伍里高于我们的队数」，看分布的上尾（见 dual-model-workflow 仓库 docs/design/2026-09-workflow-modes.md）。
    if board and best is not None and k9.get("ext_k") is not None:
        checked.append("k9_position")
        low = [float(r["score"]) for r in board if int(r["submissions"]) <= k9["ext_k"]]
        why = []
        if low:
            med = statistics.median(low)
            above = sum(1 for v in low if v > best)
            if best < med:
                why.append(f"最好分 {best:.2f} < 提交 ≤{k9['ext_k']} 次队伍的中位数 {med:.2f}（{len(low)} 队）")
            if k9.get("ext_count_above") is not None and above >= k9["ext_count_above"]:
                why.append(f"提交 ≤{k9['ext_k']} 次的队伍里有 {above} 队高于我们（阈值 {k9['ext_count_above']}）")
        if why and not state["position_fired"]:
            triggers.append({"kind": "k9_position", "id": f"pos-{len(series)}", "roles": roles,
                             "reason": "外部位置：" + "；".join(why)})
        state["position_fired"] = bool(why)
    if k9.get("day2_date") and k9.get("day2_cutline_pct") is not None and cutline is not None and best is not None:
        checked.append("k9_day2")
        line = cutline * (1 - k9["day2_cutline_pct"] / 100)
        if t >= date.fromisoformat(k9["day2_date"]) and not state["day2_fired"] and best < line:
            triggers.append({"kind": "k9_day2", "id": "day2", "roles": roles,
                             "reason": f"第 2 天对截线：最好分 {best:.2f} < 截线 {cutline:.2f} × (1 − {k9['day2_cutline_pct']}%) = {line:.2f}"})
            state["day2_fired"] = True
    # ② 停滞：新包满 N 个才判。剩余名额只算今天之后的天数（今天的名额视为已用或正在用）。
    n = k9["N"]
    checked.append("k9_stall")
    if len(series) - state["k9_last_judged"] >= n and len(series) >= n + 1:
        gain = series[-1] - series[-1 - n]
        remaining = k9.get("remaining_slots")
        if remaining is None and "end_date" in k9 and "slots_per_day" in k9:
            remaining = max(0, (date.fromisoformat(k9["end_date"]) - t).days) * k9["slots_per_day"]
        if cutline is not None and remaining is not None:
            proj_gain = gain / n * remaining
            fired = proj_gain < cutline - series[-1]
            why = f"近 {n} 包增量 {gain:.2f}，÷{n}×剩余 {remaining} 名额 = {proj_gain:.2f} < 距截线 {cutline - series[-1]:.2f}"
        elif k9.get("fixed_X") is not None:
            fired = gain < k9["fixed_X"]
            why = f"近 {n} 包合计增量 {gain:.2f} < X={k9['fixed_X']}"
        else:
            raise ValueError("k9 既没有排行榜截线 + 剩余名额，也没有 fixed_X，停滞判据算不出")
        state["k9_last_judged"] = len(series)
        if fired:
            triggers.append({"kind": "k9_stall", "id": f"stall-{len(series)}", "roles": roles,
                             "reason": "停滞：" + why})
    return checked, triggers


def run_third(proj, cfg, role, trig, stamp):
    rc = cfg["roles"][role]
    template = (proj / rc["template"]).read_text(encoding="utf-8")
    prev = sorted(p.name for p in (proj / ".workflow/reports").glob("*.md"))
    prompt = (template + f"\n\n## 本次召唤\n- 触发：{trig['reason']}\n- 项目目录：{proj}\n"
              + "- 前任报告（可读，不读对话）：" + (", ".join(prev) if prev else "无") + "\n")
    args = [CLAUDE, "-p", "--model", rc.get("model", "opus"), "--effort", rc.get("effort", "high"),
            "--permission-mode", "default", "--allowedTools", RO_TOOLS]
    if rc.get("isolated"):
        cwd = Path(tempfile.mkdtemp(prefix=f"k10-{role}-"))
        for rel in rc.get("inputs", []):
            dst = cwd / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(proj / rel, dst)
        prompt = prompt.replace(str(proj), "〔隔离：不提供项目路径〕")
    else:
        cwd = proj
    p = subprocess.run(args, input=prompt, capture_output=True, text=True, cwd=cwd,
                       timeout=rc.get("timeout_s", 1800))
    ok = p.returncode == 0 and p.stdout.strip() != ""
    # 失败记录不进 reports/：进了会被 Stop 钩子当成要回应的报告（verifier 第十轮 E）。
    out_dir = proj / (".workflow/reports" if ok else ".workflow/k10-failures")
    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"{stamp}-{role}-{trig['id']}.md"
    header = f"<!-- k10-watch: role={role} trigger={trig['kind']}:{trig['id']} rc={p.returncode} -->\n# {role} 报告（{trig['reason']}）\n\n"
    out.write_text(header + (p.stdout if ok else f"**第三者运行失败 rc={p.returncode}**\n\n```\n{p.stderr[-2000:]}\n```\n"),
                   encoding="utf-8")
    return ok, out


def doorbell(proj, cfg, reports):
    prefix = cfg.get("overseer_prefix")
    if not prefix:
        return False, "k10.json 没有 overseer_prefix"
    # 绝对路径：2026-09-26 实测，相对路径会让收件方猜错项目位置（见 k10-stop-gate.py 同类注释）。
    rel = ", ".join(str(r) for r in reports)
    msg = (f"[k10-watch] 项目 {proj} 的第三者报告已写入：{rel}。请逐条回应，"
           f"写到 {proj / '.workflow/responses'}/ 下的同名文件；未回应前，Stop 钩子会拦住全局者结束回合。")
    prompt = (f"用 ListAgents 找名字以「{prefix}」开头的会话。恰好一条时，用 SendMessage 把下面这段原样发给它，"
              f"然后只输出 SENT。零条或多条时，什么都不发，只输出 NO-MATCH <条数>。\n\n{msg}")
    args = [CLAUDE, "-p", "--model", cfg.get("doorbell_model", "haiku"), "--permission-mode", "default",
            "--allowedTools", "ListAgents,SendMessage"]
    try:
        p = subprocess.run(args, input=prompt, capture_output=True, text=True, cwd=tempfile.gettempdir(), timeout=300)
    except (subprocess.TimeoutExpired, OSError) as e:
        return False, repr(e)
    last = (p.stdout.strip().splitlines() or [""])[-1]
    return p.returncode == 0 and last.startswith("SENT"), last or p.stderr[-300:]


def main():
    if len(sys.argv) != 2:
        print("用法：k10-watch.py <project-dir>", file=sys.stderr)
        return 2
    proj = Path(sys.argv[1]).resolve()
    wf = proj / ".workflow"
    try:
        mode = read_mode(proj)
    except ValueError as e:
        log(f"{proj}: {e}")
        return 2
    cfg_path = wf / "k10.json"
    if not cfg_path.exists():
        log(f"{proj}: 模式={mode or '未选'}；缺 .workflow/k10.json，范围算不出")
        return 2
    cfg = json.loads(cfg_path.read_text(encoding="utf-8"))
    state_path = wf / "k10-state.json"
    state = {"calendar_fired": [], "k9_last_judged": 0, "position_fired": False, "day2_fired": False, "pending": []}
    if state_path.exists():
        state.update(json.loads(state_path.read_text(encoding="utf-8")))

    def save():
        state_path.write_text(json.dumps(state, ensure_ascii=False, indent=1), encoding="utf-8")

    code = 0
    try:
        checked, triggers = judge_calendar(cfg, state)
        scores = board = None
        try:
            scores = read_tsv(wf / "scores.tsv")
            board = read_tsv(wf / "leaderboard.tsv")
            # 在副本上判，全部成功后再合并：否则先写进去的 position_fired / day2_fired
            # 会在后面的停滞判据抛错时被 finally 存下来，触发就永久丢了（verifier 第十一轮 J）。
            k9_state = copy.deepcopy(state)
            c2, t2 = judge_k9(cfg, k9_state, scores, board)
            k9_state["last_k9_error"] = None
            state.update(k9_state)
            checked += c2
            triggers += t2
        except (ValueError, KeyError, OSError) as e:
            log(f"{proj}: K9 判定失败：{e}（K9 本轮不计入，状态不变；日历照常判）")
            state["last_k9_error"] = f"{datetime.now(timezone.utc):%Y-%m-%d %H:%M}Z {e}"
            code = 2
        log(f"{proj}: 模式={mode or '未选'}；查了 {len(checked)} 个触发条件（{', '.join(checked) or '无'}；"
            f"分数 {0 if scores is None else len(scores)} 行，排行榜 {0 if board is None else len(board)} 行），"
            f"触发 {len(triggers)} 个，待办 {len(state['pending'])} 个")
        # 触发先入队并落盘，再调模型：中途崩溃也不会每轮重新召唤（verifier 第十轮 C）。
        for trig in triggers:
            for role in trig["roles"]:
                state["pending"].append({"trig": trig, "role": role, "attempts": 0})
            if trig["kind"] == "calendar":
                state["calendar_fired"].append(trig["id"])
        save()
        stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%MZ")
        written = []
        for job in list(state["pending"]):
            job["attempts"] += 1
            save()
            trig, role = job["trig"], job["role"]
            try:
                ok, out = run_third(proj, cfg, role, trig, stamp)
            except (subprocess.TimeoutExpired, OSError, KeyError, UnicodeDecodeError) as e:
                ok, out = False, None
                log(f"  {trig['id']} {role}: 启动失败 {e!r}")
            if ok:
                written.append(out)
                state["pending"].remove(job)
                log(f"  {trig['id']} {role}: OK → {out}")
            else:
                code = code or 1
                if job["attempts"] >= MAX_ATTEMPTS:
                    state["pending"].remove(job)
                    log(f"  {trig['id']} {role}: 失败 {job['attempts']} 次，放弃（记录在 .workflow/k10-failures/）")
                else:
                    log(f"  {trig['id']} {role}: 失败第 {job['attempts']} 次，下一轮重试")
            save()
        if written:
            ok, info = doorbell(proj, cfg, written)
            log(f"  门铃：{'已送达' if ok else '未送达'}（{info}）")
            code = code or (0 if ok else 1)
    finally:
        save()
    return code


if __name__ == "__main__":
    sys.exit(main())
