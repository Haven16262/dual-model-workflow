# Dual-Model Workflow

A lightweight protocol for pairing two AI coding models — one as **Overseer**, one as **Worker** — coordinated through three plain Markdown files. Solves single-model context exhaustion and role confusion.

**[English](#english) · [中文](#中文)**

> Runs on the [Claude Code](https://claude.com/claude-code) CLI — install that first; this repo does not install it. A Claude account is **optional**: either role can run on any Anthropic-compatible model endpoint. See [Prerequisites](#prerequisites) · 运行在 Claude Code 命令行之上,需先自行安装,本仓库不负责安装。Claude 账号**不是必须的**:两个角色都可以接任意 Anthropic 兼容的模型端点,见[前置条件](#前置条件)。

---

## English

### The problem

When you use one AI model for a long coding session, two things go wrong:

1. **Context exhaustion** — as the conversation grows, the model loses early context, repeats mistakes, and drifts off course.
2. **Role confusion** — you want it to make architecture decisions, it edits code details; you want it to execute, it keeps asking you for direction.

This workflow splits the work across **two models with separate roles**, and manages the shared state in three files so each model only does what it's good at.

### Two roles

- **Overseer (`cc`, any model — e.g. Claude)** — direction, decisions, review. Does not read large numbers of files, does not iterate on details. Steps in only at key moments: set architecture at kickoff, decide when the Worker hits a fork, review at phase boundaries.
- **Worker (`cc-alt`, any model — e.g. DeepSeek)** — execution, iteration, detail implementation. Reads files, looks things up, writes code, fixes bugs. The role that actually does the work.

The two roles run in separate terminal sessions: `cc` starts the Overseer, `cc-alt` starts the Worker. (`cc` and `cc-alt` are shell functions defined by this repo's helper file — see the Quick start — not commands that ship with Claude Code.)

### Three files

- **`WORKFLOW.md`** — the rules: each role's responsibilities, switch trigger conditions, and the `context.md` write formats. Both models read this on startup so behavior stays consistent.
- **`CLAUDE.md`** — project-level startup instructions: every session must (1) read `WORKFLOW.md`, (2) read `context.md` (top status block first, then latest history), (3) restate "I am [role], current task is: [summary]" and begin.
- **`context.md`** — the core. A top `## Current State` block (overwritten on each write — the latest task list) plus an append-only history log (timestamped records of every decision and execution step).

These three live in every project that uses the workflow. Two optional documents sit at the repository level instead and are not part of the per-project set: [`CROSS-MACHINE.md`](CROSS-MACHINE.md) (Overseer and Worker, or two Overseers, on different machines) and [`channel-starter/`](channel-starter/) (a dedicated letter-channel repository for projects that share no repository).

### Prerequisites

This repository is a set of templates and shell helpers that sit **on top of** the [Claude Code](https://claude.com/claude-code) command-line tool. Claude Code is only the runtime both roles run in; the models behind the roles are your choice. This repo does not install Claude Code and does not replace it. Before the Quick start:

1. **Claude Code installed.** Follow the official instructions at <https://claude.com/claude-code>. To check: `claude --version` prints a version. If `claude` is missing, `cc` and `cc-alt` fail with `command not found` — and that is the *last* thing to fail: sourcing the helper and running `cc-init` both succeed without Claude Code, so nothing earlier warns you.
2. **A model for each role, and a way to authenticate to it.** A Claude account is optional. Each role is just a `claude` process pointed at some model endpoint:
   - `cc` (Overseer) uses whatever your default `claude` configuration points at — a Claude login, or `ANTHROPIC_*` environment variables / `settings.json`, see "Using models other than Claude" below.
   - `cc-alt` (Worker) ships with one example, DeepSeek's Anthropic-compatible endpoint, so the Quick start asks for a `DEEPSEEK_API_KEY`. For another endpoint, edit the environment variables in `cc-alt`.
   - Both roles may be non-Claude models. Checked on 2026-10-15 (Claude Code 2.1.300, Linux): in a fresh home directory with no Claude login at all, `claude -p` with only `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN` and the model variables pointed at DeepSeek's Anthropic-compatible endpoint returned a normal answer and created no credentials file. Not checked: the interactive first-run screens (print mode skips them), or other endpoints. Note that Claude Code's own setup docs say it requires a Claude or Console account, or a supported cloud provider — a third-party Anthropic-compatible endpoint works today but is outside what those docs promise, so it may change.
3. **Shell and tools.** Linux / macOS: bash and git. Windows: PowerShell plus Git for Windows — Git Bash comes with it, and the security precheck script needs bash. (Claude Code itself does not need Git for Windows: without it, it falls back to PowerShell for shell commands.) Python 3 is needed only for the optional pieces below.
4. **Claude Code version.** Developed and tested on Claude Code 2.1.x (latest check: 2.1.300, on Linux). Only the cross-session notification feature has a verified version floor (see "Let the sessions notify each other"); no other floor has been checked, so if something behaves differently, upgrade Claude Code first.

**What is core, what is optional.** The Quick start sets up the core: the templates, the helper (`cc` / `cc-alt` / `cc-init`), and the security precheck. These are optional extras — skip them on a first run:

- **Worker permission guard** (Python 3) — see "The Worker permission guard".
- **K10 third-party review** (`k10-*.py`, step 6 of the Linux Quick start) — an independent reviewer session for competition-mode projects. The watcher needs cron + flock; it is not set up for Windows.
- **Cross-session notification** — same-machine works with any model; across machines it needs a Claude account on both ends (details below and in [`CROSS-MACHINE.md`](CROSS-MACHINE.md)).

#### Using models other than Claude

Set the endpoint for the Overseer before running `cc` (or put the same keys under `env` in the `settings.json` that `cc` reads):

```bash
export ANTHROPIC_BASE_URL="https://<your-endpoint>/anthropic"
export ANTHROPIC_AUTH_TOKEN="<your-token>"     # never empty, never unset — see the warning below
export ANTHROPIC_MODEL="<your-model-name>"
# The critic subagent asks for `haiku` and competition mode asks for `opus`. On a non-Claude
# endpoint those aliases must resolve to a model your endpoint actually serves — `cc-alt` does
# this for every tier, and so should you (competition mode also honours DUAL_MODEL_MODEL):
export ANTHROPIC_DEFAULT_OPUS_MODEL="<your-model-name>"
export ANTHROPIC_DEFAULT_SONNET_MODEL="<your-model-name>"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="<your-model-name>"
```

> **Warning — never leave the token empty or unset when `ANTHROPIC_BASE_URL` points at a non-Anthropic host.** Observed on Claude Code 2.1.272 (2026-09-15): with a custom base URL and no token, Claude Code did not error out; it fell back to the machine's Claude login and sent that account's OAuth token to the custom endpoint. `ANTHROPIC_AUTH_TOKEN=$VAR` with an empty `$VAR` takes the same path, and so does assigning an empty string to `$env:X` in PowerShell (which deletes the variable). `cc-alt` checks that the key is non-empty and aborts; any launcher you write must do the same. Without a Claude login on the machine there is nothing to leak, but keep the check anyway.

Messaging between sessions does not depend on the model behind them: same-machine `SendMessage` works between two sessions that both run on third-party endpoints (observed with DeepSeek-backed sessions on the author's VPS), and Claude Code's docs, as checked on 2026-09-18, list same-machine messaging as available on every provider from 2.1.248. Run `/list-agents` to confirm it is on in your session. Setting any of `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, `DISABLE_TELEMETRY`, `DO_NOT_TRACK` or `DISABLE_GROWTHBOOK` silently turns the feature off (per the author's notes; `/list-agents` is the check). **Across machines** it is different: that route needs a Claude account on both ends — see [Let the sessions notify each other](#let-the-sessions-notify-each-other) and [`CROSS-MACHINE.md`](CROSS-MACHINE.md).

### Repository layout

```
templates/   # markdown templates — platform-neutral, shared by both platforms
scripts/     # security-scan.sh (bash, both platforms via Git Bash)
#              worker_guard.py + cc_allow_once.py + worker_guard_test.sh
#              dual-model-mode.sh (workflow-mode rules, called by the launchers)
#              k10-watch.py / k10-stop-gate.py / k10-subagent-report.py (optional: third-party reviews, K10)
#              tests/ (bash test_dual_model_mode.sh ; bash test_k10.sh)  — Linux only; not ported to Windows
docs/design/ # design records (why the templates say what they say)
skills/      # allow-once — install into ~/.claude/skills/
channel-starter/ # optional: starter kit for a dedicated letter-channel repository (see CROSS-MACHINE.md)
linux/       # bash helpers (cc / cc-alt / cc-init) — source into ~/.bashrc
windows/     # PowerShell helpers (same commands) — dot-source into $PROFILE
```

Only the shell helpers differ per platform; everything else (templates, security scan, license) is shared at the repo root. To sync a workflow change across machines: `git pull` on each machine — the sourced helper file updates in place.

One real behavioral difference between the two ports: **model switching**. The Linux version injects the DeepSeek endpoint via per-command environment variables at launch; the Windows version passes `claude --settings ~\.claude\settings.deepseek.json`. Both are scoped to a single session, so two terminals never interfere. Do not switch models by overwriting `~\.claude\settings.json` — that file is shared by every running Claude Code process, and rewriting it hot-reloads into sessions already running in other terminals. See the header comments in each helper file.

### Quick start — Linux / macOS (bash)

```bash
# 0. Prerequisites (see above) — stop here if this prints the "not found" line
command -v git >/dev/null || echo "git not found"
command -v claude >/dev/null && claude --version || echo "claude not found — install Claude Code first (see Prerequisites)"

# 1. Clone
git clone https://github.com/Haven16262/dual-model-workflow.git
cd dual-model-workflow

# 2. Make templates discoverable (default location)
mkdir -p ~/.dual-model/templates
cp -r templates/. ~/.dual-model/templates/
#   (the trailing dot copies hidden entries like .claude/ too)
#   (or: export DUAL_MODEL_TEMPLATES=/abs/path/to/dual-model-workflow/templates)

# 2b. Install the scripts: security precheck (Overseer, before every review) and
#     workflow-mode rules (read by cc / cc-alt) are core; the k10-*.py files are the
#     optional third-party-review hooks + watcher — copying them is harmless
mkdir -p ~/.claude/scripts
cp scripts/security-scan.sh scripts/dual-model-mode.sh scripts/k10-*.py ~/.claude/scripts/

# 3. Export your DeepSeek key in your shell profile (NEVER commit this)
echo 'export DEEPSEEK_API_KEY="sk-your-deepseek-key"' >> ~/.bashrc

# 4. Source the helpers
echo 'source '"$PWD"'/linux/dual-model.sh' >> ~/.bashrc
source ~/.bashrc

# 5. In any project directory, initialize the workflow
cd /path/to/your/project
cc-init        # copies WORKFLOW.md + CLAUDE.md + context.md + .claude/{commands,agents,settings.json} + .workflow/

# 6. (optional — competition-mode projects only) schedule the K9 watcher — see WORKFLOW.md, section K10
#    */30 * * * * flock -n /tmp/k10-<proj>.lock ~/.claude/scripts/k10-watch.py /path/to/project >> /path/to/k10.log 2>&1
```

> **Naming note:** `cc` shadows the system C compiler (`/usr/bin/cc`) in interactive shells. If you do C development, rename the functions in `linux/dual-model.sh` (e.g. `dm`, `dm-ds`, `dm-init`).

### Quick start — Windows (PowerShell)

```powershell
# 0. Prerequisites (see above)
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Host "git not found" }
if (Get-Command claude -ErrorAction SilentlyContinue) { claude --version } else { Write-Host "claude not found - install Claude Code first (see Prerequisites)" }

# 1. Clone
git clone https://github.com/Haven16262/dual-model-workflow.git
cd dual-model-workflow

# 2. Make templates discoverable (default location)
New-Item -ItemType Directory -Force "$env:USERPROFILE\.dual-model\templates" | Out-Null
Copy-Item -Recurse -Force templates\* "$env:USERPROFILE\.dual-model\templates\"
Copy-Item -Recurse -Force templates\.claude "$env:USERPROFILE\.dual-model\templates\"
Copy-Item -Recurse -Force templates\.workflow "$env:USERPROFILE\.dual-model\templates\"
#   (the wildcard skips hidden dirs, so .claude/ and .workflow/ need their own copy)
#   (or: $env:DUAL_MODEL_TEMPLATES = "C:\abs\path\to\dual-model-workflow\templates")

# 2b. Install the security precheck script (runs under Git Bash, which comes with Git for Windows — Claude Code does not ship it)
New-Item -ItemType Directory -Force "$env:USERPROFILE\.claude\scripts" | Out-Null
Copy-Item scripts\security-scan.sh "$env:USERPROFILE\.claude\scripts\"
#     K10 hooks (optional, Python): the hook command tries python3 then python and only uses one that
#     actually runs (Git Bash may find a Store stub named python3); scripts force UTF-8 I/O.
#     2026-09-29: byte-level checked on MSI; end-to-end in CC still pending. k10-watch.py needs
#     cron + flock and is NOT set up for Windows.
Copy-Item scripts\k10-*.py "$env:USERPROFILE\.claude\scripts\"

# 3. Prepare the settings file for model switching (NEVER commit the key)
#    ~\.claude\settings.deepseek.json  — DeepSeek endpoint env + API key (Worker)
#    (the Overseer just uses your normal ~\.claude\settings.json — nothing to prepare)

# 4. Dot-source the helpers in your PowerShell profile
Add-Content $PROFILE ". `"$PWD\windows\dual-model.ps1`""
. $PROFILE

# 5. In any project directory, initialize the workflow
cd C:\path\to\your\project
cc-init        # copies WORKFLOW.md + CLAUDE.md + context.md + .claude/{commands,agents,settings.json} + .workflow/
```

Then use two terminals: `cc` for the Overseer, `cc-alt` for the Worker. Each silently injects the role into the system prompt (via `--append-system-prompt`, not sent as a chat message — your first message stays free for whatever you want to say) and reads `WORKFLOW.md` / `context.md` to restore state.

After you pick a role, the helper also asks for a **topic for this round** (optional, Enter to skip). Together with the machine tag, the project directory, and the role it forms the session name, passed via `--name`, in four segments:

```
<machine>-<project-dir>-<role>-<topic>        # e.g. vps-bili-overseer-login-rework
<machine>-<project-dir>-<role>-<MMDD-HHMM>    # fallback when you skip the topic
```

Each segment earns its place; drop one and something breaks:

- **Machine tag** — read from `~/.claude/machine-tag`. It is *not* there to help the AI tell machines apart: across machines a peer shows up under its Remote Control name, which already carries the hostname. It is for **you**. The same git repository checked out on two machines has the same directory name, so without the prefix your session list on claude.ai and on your phone shows two byte-identical rows and you have to open one to find out which machine it is. No tag file, no prefix — the other three segments are unchanged.
- **Project directory** — with two projects running the workflow at once, a fixed name like `worker` would deliver a handoff to the *other project's* Worker. Worse than no automation at all.
- **Role** — tells the two terminals of one project apart, and is what a handoff is aimed at.
- **Topic** — without it every launch of the same project produces an identical name, and the `/resume` picker fills with rows you can't tell apart. `--name` also **overrides** the summary title Claude Code would have generated on its own, so a fixed name doesn't just fail to help — it replaces a useful title with a useless one.

The cost: the sender can no longer compute the peer's full name from its own cwd, since the topic is typed at the peer's own launch. It has to look the name up before sending — see the next section.

### Switching roles

The Worker finishes a phase or hits a decision it can't make, writes to `context.md`, and says *"written to context.md, please switch to the Overseer."* You go to the Overseer terminal and type:

> *The Worker changed something, check the context file.*

The Overseer reads it, gives a decision, writes to `context.md`, and says *"decision written, switch back to the Worker."* You go to the Worker terminal and type:

> *The Overseer changed something, check the context file.*

These two phrases are the switch signals — the model reads `context.md` on receiving them, so you never have to re-explain the background.

**Slash command alternative:** the same two switch signals are also wired up as slash commands (defined in `templates/.claude/commands/`):

- In the Overseer terminal: `/as-overseer` ≡ *"The Worker changed something, check the context file"* (i.e. "I'm now stepping in as Overseer")
- In the Worker terminal: `/as-worker` ≡ *"The Overseer changed something, check the context file"* (i.e. "I'm now stepping in as Worker")

(The `as-` naming is mnemonic: you state the role you're about to take. It's also faster to type than `from-` since `a` and `s` are adjacent on QWERTY.)

Same semantics, less typing. Hand-typed phrases still work.

### Let the sessions notify each other

The two "walk over to the other terminal and type" steps above can be skipped. Claude Code supports cross-session messaging (`SendMessage` + `ListAgents`): with both terminals running, whichever side just wrote `context.md` notifies the other directly, and the other picks up via the full `/as-worker` / `/as-overseer` procedure.

Two version floors: **macOS / Linux / WSL 2 need ≥ 2.1.224, native Windows ≥ 2.1.234.** Check a session with `/list-agents` (also `/peers`) — if the command isn't recognized, the session doesn't have the feature.

The sender can compute the first three segments of the peer's name but not the last. So **run `ListAgents` before sending**, find the row whose name starts with `vps-bili-worker-`, and send to the full name printed there. **Exactly one match** — otherwise fall back to the manual handoff. That lookup is part of the procedure, not troubleshooting.

**Re-check before every send.** Don't reuse a name from an earlier lookup, and don't use a list your user pasted — a peer's name changes as soon as its terminal is restarted (observed: the user was looking at `claude-code-b7` while the tool already returned `claude-code-3a`). A name that matches exactly one live session delivers on the bare name; the `[ref]` suffix is only needed when several sessions share it. You can also `@`-mention a session in your own prompt to name the target directly.

One iron rule: **a message only wakes the other side and points at the file. Decisions always go into `context.md`.**

> This isn't fastidiousness. The core promise of this workflow is that either side can open a fresh session and reconstruct the entire decision chain from files alone. Messages are ephemeral; what doesn't reach a file didn't happen. Once decisions start travelling by message that promise is void — and it fails silently: everything works now, and the chain turns out to be broken only when someone goes back to trace it.

When a send fails (peer terminal not running, name doesn't match, version or platform too old), **fall back to the manual handoff and don't retry.** That's what keeps this an optional accelerator rather than a new required path: when the automatic channel is down, the workflow degrades to exactly what it was before.

**Optional: let the platform watch for you.** When the Overseer hands work off, it can pass `notify_when_idle` (≥ 2.1.236, same machine only) to be told once when the Worker next goes idle. The upside is that it doesn't depend on the Worker remembering to send anything; the cost is that it only says "idle", not "handoff ready" — you still read `context.md` to see whether a new handoff block exists.

**Platform status:** cross-session messaging started out macOS- and Linux-only; native Windows caught up in 2.1.234, so all three are covered. Same-machine delivery goes over a local socket (a named pipe on Windows) and never touches Anthropic servers; **across machines** (say a VPS and your laptop) both ends must be signed in with a Claude account and connected to Remote Control, and the message is relayed through Anthropic servers. Without a Claude account that route is closed — keep the shared-repository part of the handoff and carry the one-line pointer by any other channel (chat, email, a webhook, another open-source messenger, something you build); see [`CROSS-MACHINE.md`](CROSS-MACHINE.md). Note that a session inside WSL 2 and a native Windows session on the same computer **can't see each other** — different home directories, different socket types.

Organizing work *across* machines — using a shared git repository as the handoff medium, how addressing differs, and the Linux ↔ Windows line-ending/path/timezone traps — is covered separately in [`CROSS-MACHINE.md`](CROSS-MACHINE.md). You don't need it for same-machine use.

> **A trap when testing:** a terminal spawned from inside a Claude Code session inherits the `CLAUDE_CODE_CHILD_SESSION` environment variable, and such a session **doesn't register as a peer** — it simply never appears in `ListAgents` (the terminal says `Transcript saving is off — inherited CLAUDE_CODE_CHILD_SESSION marker`). You won't hit this typing `cc` in a clean terminal, but anyone scripting a test of this mechanism will, and it looks exactly like "the name doesn't match".

**Don't expect it to drive an unattended loop.** A cross-session message sent to a session that skips permission prompts is held for your approval by design. What this mechanism saves is typing and context-switching — not watching.

### The Worker permission guard

> **Off by default and entirely optional.** Nothing in this repository installs the guard, and the repository ships no permission rules (`allow` / `ask` / `deny`) of its own — the `ask` rules mentioned below are from the author's personal `settings.json` and are not included. Unless you install the guard, a Worker runs under whatever permission configuration you already have, and nothing stops it from running `git push`: the "Workers don't push" rule is then only text in `WORKFLOW.md`. Don't want the guard? Skip this section and delete `scripts/worker_guard.py`, `scripts/cc_allow_once.py`, `scripts/worker_guard_test.sh` and `skills/allow-once/`. Want it? The install steps below are all it takes. The `WORKFLOW.md` template has a section titled 命令被守卫拦下时 ("when the guard blocks a command") that assumes the guard is installed — ignore or delete it if you skip the guard.

A Worker session cannot reach Remote Control: `cc-alt` points `ANTHROPIC_BASE_URL` at a local gateway, and Claude Code refuses Remote Control whenever that variable names a host other than `api.anthropic.com`. Permission prompts, meanwhile, never time out. So a Worker that trips a prompt while you are away is not waiting — it is hung, indefinitely. (Remote Control itself needs a Claude account; without one no session can use it, and an unanswered prompt hangs just the same.)

The guard is a `PreToolUse` hook that denies those commands *before* the dialog opens, which is what makes "skip it and do something else" possible at all.

| Class | Commands | Behavior |
|---|---|---|
| Hard deny | `git push` | No release path. The Worker commits, records state, and hands off to the Overseer, which reviews and publishes on its own authority. |
| Deny + window | `ssh`, `chmod` | Queued automatically. You type `/allow-once` to open a 10-minute window; the Worker retries and the normal prompt fires. |

The set mirrors the `ask` rules in the *reference* `settings.json` (`chmod`, `ssh`, `git push`) — on that machine those are the only prompts a Worker can trip. **Your machine may have no `ask` rules at all**, in which case these commands still prompt through the default flow outside auto mode, and the guard is then the *only* thing standing between the Worker and an unanswerable dialog. Check your own rules before assuming the two lists line up.

Two properties worth stating:

* **Opening the window is not authorization.** It only lets the prompt appear; permission still comes from you answering it.
* **The model cannot open its own window.** The `allow-once` skill sets `disable-model-invocation: true`, and its `!` line runs at expansion time, before the model sees anything — so arming is a human act by construction.

Install (both platforms — the scripts are Python, not shell):

```bash
cp scripts/worker_guard.py scripts/cc_allow_once.py ~/.claude/scripts/
mkdir -p ~/.claude/skills/allow-once && cp skills/allow-once/SKILL.md ~/.claude/skills/allow-once/
echo vps > ~/.claude/machine-tag        # or: msi, n1, ... — one short tag per machine
```

Then add the hook to the **Worker-only** settings file (`~/.claude/settings.deepseek.json`), never to `settings.json` — the Overseer must keep its normal prompts, since, with a Claude account, it is the session that can reach your phone through Remote Control:

```json
{ "matcher": "Bash",
  "hooks": [{ "type": "command",
              "command": "python3 -S \"$HOME/.claude/scripts/worker_guard.py\"",
              "timeout": 10 }] }
```

On Windows, **write the interpreter's full path** in both the hook command and `SKILL.md` — for example `E:/Anaconda/python.exe`. Do not assume `python3` works because it resolves: on a default Windows install `python3` is a Microsoft Store stub that sits on PATH, is not an interpreter, and exits 9009 with *"Python was not found"*. A hook pointed at it fails, and a failing hook is a **fail-open** hook. Bare `python` may work in Git Bash and still not work from the hook, whose PATH is not Bash's.

Inside `SKILL.md` the interpreter appears **twice** — in `allowed-tools` and in the `!` line — and the two must match *character for character*. Claude Code checks the injected command against the rule and aborts the whole invocation when it doesn't come back `allow`, so editing one and forgetting the other doesn't degrade the skill, it kills it.

**Encoding matters here too.** These scripts pin `sys.stdout` to UTF-8 in code rather than relying on `-X utf8` in the hook command, because Claude Code parses hook stdout as UTF-8 while Python defaults to the locale encoding (cp936 on a Simplified Chinese Windows). When that mismatch happens the JSON fails to parse, `permissionDecision` is lost, and the command runs. **A guard that fails open is worse than no guard** — it makes people believe `git push` was blocked when it wasn't. The test suite has a dedicated case for this; don't skip it.

**Linux users: check that your `cc-alt` actually passes the file.** The endpoint comes from environment variables there, so `settings.deepseek.json` is optional and easy to forget — and a hook in a file nobody loads fails *silently*. The helper in `linux/dual-model.sh` passes it when it exists; if you are running a copy sourced before this feature landed, re-source it.

Verify the install:

```bash
bash scripts/worker_guard_test.sh          # or: bash scripts/worker_guard_test.sh python
```

22 classification cases, including the ones that motivated the parser: `git log --grep push` and a heredoc body containing a `git push` example must **not** be blocked, because the hard-deny path has no release valve and a false positive strands the Worker on a harmless command.

### Trigger conditions (Worker → Overseer)

The Worker must stop and switch to the Overseer when:

1. There's an architecture fork with multiple options it can't choose between.
2. It hits a security- or performance-relevant design decision.
3. It finished a complete module and needs direction confirmed before continuing.
4. Two consecutive attempts still don't solve a problem.

Condition 4 matters — rather than let the Worker burn tokens trial-and-erroring, switch to the Overseer for a fresh angle.

### The review mechanism — and why

Early versions had a hidden flaw: **the Overseer was nominally supposed to "review the Worker's output at phase boundaries," but it wasn't actually reviewing anything.**

The cause was the write format. The Worker only wrote a *completion summary* and *task progress* — all **results** (what got done), no **decisions** (how, what was touched). The Overseer, holding a results summary, had no way to tell whether direction had drifted or a security pitfall was hit. Review stayed at the "looks done" surface.

The fix is not to make the Overseer read all the code (that violates its "don't read large numbers of files" principle), but to make the Worker surface key decisions on delivery. The Worker write format now carries a mandatory four-item checklist:

```
**Key decisions:** (answer every item explicitly; write "none" if none — never leave blank)
- Architecture / interface changes: ...
- Security-relevant: touches auth / secrets / user input / SQL / file paths / outbound requests?
- Deviations from plan: ...
- Unresolved doubts: things pushed past without confidence
```

This deliberately separates **fact reporting** from **risk judgment**: the Worker only answers factually ("did you change an interface", "did you touch these security-sensitive surfaces") — answerable even without understanding the risk; the Overseer judges the risk. "Unresolved doubts" is the single highest-value line — it catches the blind spot where **the Worker isn't blocked, so it never triggers a switch, but it's actually unsure**. That case used to fall straight through the net.

A paired hard rule for the Overseer: **whenever the security item is non-empty, it must invoke the `critic` subagent** (defined in [`templates/.claude/agents/critic.md`](templates/.claude/agents/critic.md), runs on Haiku) to read the relevant files and return a structured audit, rather than relying on the summary. This operationalizes the "must read code" rule without making the Overseer itself read large numbers of files — the critic does the reading and reports back; the Overseer judges from the report.

That still leaves a gap: the escape hatch is gated on the Worker's self-report, and models reflexively fill "none" (see the caveat below). The fix is an objective trigger that doesn't depend on self-reporting: before every review, the Overseer runs [`scripts/security-scan.sh`](scripts/security-scan.sh) — a pure local `grep` over the diff's added lines (zero token cost, no model call) that flags security-sensitive keywords (auth/secrets, SQL, command execution, path traversal, outbound requests). **A hit or a non-empty security item — either one — forces the `critic` invocation.** A hit doesn't mean there's a real problem, only that review gets escalated to mandatory; the script is a trigger, not a verdict.

### Why this patch doesn't auto-work (the honest caveat)

Be honest about one thing: the whole mechanism rests on the **Worker self-reporting honestly**, and the Worker is a smaller/cheaper model. Models tend to reflexively fill all four items with "none" to close out faster — especially "unresolved doubts" (admitting uncertainty is exactly what models least want to do). Once it writes "none" on the security item where it shouldn't, the "security non-empty → must read code" escape hatch is bypassed by the empty fill, and the mechanism spins idle.

So the countermeasure is not another format change — it's Overseer behavior: **early in working with a given Worker model, even when it writes "none" on the security item, spot-check the actual diff once or twice** to learn whether this Worker self-reports honestly or reflexively fills "none." Calibrate how much you trust the checklist accordingly, instead of trusting it by default. Mechanism design can only go so far; the rest is calibration from real runs.

### context.md write formats

See [`templates/WORKFLOW.md`](templates/WORKFLOW.md) for the authoritative, copy-paste formats (Overseer write, Worker write, Worker→Overseer handoff). Once the format is consistent, either side opening a new session can reconstruct the full decision chain from the history log — no more "no idea why we did it this way last time."

### Related work

Splitting AI coding work across a stronger "planner / architect" model and a weaker / cheaper "executor" model is a well-established pattern. This repo is one specific flavor of it, not a novel design. Prior art worth knowing about (each one's status was checked against GitHub on 2026-10-15):

**Established frameworks:**
- [aider](https://github.com/Aider-AI/aider) — `--architect` mode pairs a planner model with an editor model in a single CLI. The most direct conceptual parent of this repo's idea. Still maintained (last commit 2026-05-22); the option is still in its argument list.
- [MetaGPT](https://github.com/FoundationAgents/MetaGPT) (moved from `geekan/MetaGPT`), [CrewAI](https://github.com/crewAIInc/crewAI), [LangGraph](https://github.com/langchain-ai/langgraph) — multi-agent frameworks with role-based orchestration; planner / executor is one of the canonical role splits they support. CrewAI and LangGraph are under active development; MetaGPT's last commit is from 2026-01-21.
- [AutoGen](https://github.com/microsoft/autogen) — now in **maintenance mode**: no new features, community-managed. Its README sends new users to the successor, [Microsoft Agent Framework](https://github.com/microsoft/agent-framework).
- [cline](https://github.com/cline/cline) — IDE-embedded agent with Plan / Act mode separation; actively developed, now also offered as an SDK and a CLI. [Roo Code](https://github.com/RooCodeInc/Roo-Code) (formerly `RooVetGit/Roo-Cline`) has been **archived** (read-only); its last release was v3.54.0 on 2026-05-15.

**Directly overlapping smaller repos** (created between March and May 2026, before this one, which dates from 2026-05-19):
- [chewwwwwwwwww/claude-codex-hybrid-kit](https://github.com/chewwwwwwwwww/claude-codex-hybrid-kit) — Claude Code and Codex split the work through one Markdown file per issue (`issue-N.md`) as the bus, driven by explicit slash commands (`/scope → /architect → /build → /review → /verify`): Claude scopes, builds and verifies, Codex architects and reviews, and you trigger each step by hand. Uses Codex instead of DeepSeek and fixes the flow as a pipeline. Small (2 stars); last commit 2026-04-27.
- [SelimCakil/claude-deepseek-architect](https://github.com/SelimCakil/claude-deepseek-architect) — Claude as architect with DeepSeek, Kimi and Gemini as developers: independent parts are delegated in parallel through per-provider launcher profiles (separate Claude Code config directories), with an optional MCP server (houtini-lm) for text hand-off. Dispatch is automatic rather than human-mediated. The README is in Turkish. Last commit 2026-07-22.
- [evan-e2438927/sdlc-workflow](https://github.com/evan-e2438927/sdlc-workflow) — a heavier SDLC pipeline packaged as a skill plugin for Claude Code and Codex: Claude Code writes, Codex CLI reviews at formal gates, browser automation verifies (`proposal → apply → qa → accept → pr`), and one command (`doit`) chains every stage through to a pull request. 27 stars; last commit 2026-09-26.

**Also found in a GitHub search on 2026-10-15** — judged from each repo's one-line summary only; not examined or tried:
- [tristanMatthias/bot2bot](https://github.com/tristanMatthias/bot2bot) — coordination between multiple Claude Code sessions, aimed at an "overseer / worker" setup.
- [joancarvajal80/sfcrew](https://github.com/joancarvajal80/sfcrew) — Claude Code as architect plus headless DeepSeek / GLM / Claude runners, coordinated through a `tasks.csv`.
- [aravindhsampath/agentic-template](https://github.com/aravindhsampath/agentic-template) — a project template with architect and engineer subagents and multi-model code review (DeepSeek + Kimi).

**Where this repo differs (small, but real):**
- **Human-mediated switching with explicit trigger phrases**, rather than programmatic dispatch (as in claude-deepseek-architect and sdlc-workflow's `doit`). claude-codex-hybrid-kit is also human-triggered, so that part is not unique; what differs here is that the shared state is a single append-only `context.md` per project rather than one file per issue. Slower, but transparent and dependency-free — works with just Claude Code itself.
- **The four-item "Key Decisions" checklist** that the Worker must fill on every delivery, separating fact-reporting from risk-judgment.
- **An honest caveat about why the checklist doesn't auto-work** — the Worker model may reflexively answer "none" and the Overseer must spot-check diffs to calibrate trust. I found no discussion of this limitation in the READMEs of the repos listed above (checked 2026-10-15; README-level reading only).

If you want a more automated or heavier-weight solution, prefer aider's architect mode or one of the actively maintained multi-agent frameworks above. This repo is for the case where you want the dual-model split with no extra dependencies beyond Claude Code itself.

### License

MIT — see [LICENSE](LICENSE).

---

## 中文

### 问题

用单个 AI 模型做长时间开发,有两个常见问题:

1. **上下文耗尽** —— 对话越长,模型越会丢失早期上下文,反复犯同样的错,或者做着做着把方向带偏。
2. **角色混乱** —— 你想让它做架构决策,它去改代码细节;你想让它执行,它却反复问你方向。

这套工作流的思路是:**把两个模型的角色分开**,用三个文件管理协作状态,让每个模型只做自己擅长的事。

### 两个角色

- **全局者(`cc`,任意模型,如 Claude)** —— 负责方向、决策、审查。不读大量文件,不做迭代修改,只在关键节点介入:项目启动定架构,工作者遇到分歧给决策,阶段完成做 review。
- **工作者(`cc-alt`,任意模型,如 DeepSeek)** —— 负责执行、迭代、细节实现。读文件、查资料、写代码、改 bug,是实际干活的角色。

两个角色跑在不同的终端 session 里,`cc` 启动全局者,`cc-alt` 启动工作者。(`cc` 和 `cc-alt` 是本仓库 helper 文件定义的 shell 函数,见快速开始,不是 Claude Code 自带的命令。)

### 三个文件

- **`WORKFLOW.md`** —— 游戏规则:两个角色各自的职责、触发切换的条件、`context.md` 的写入格式。每次 session 启动两个模型都先读它,确保行为一致。
- **`CLAUDE.md`** —— 项目级启动指令:每次 session 必须 (1) 读 `WORKFLOW.md`,(2) 读 `context.md`(先看顶部当前状态,再看最新历史),(3) 复述「我是[角色],当前任务是:[摘要]」再开始。
- **`context.md`** —— 整个工作流的核心。顶部 `## 当前状态`(每次写入覆盖,放最新任务清单)+ 仅追加的历史记录(每次写入留一条带时间戳的记录)。

这三个文件存在于每个使用该工作流的项目里。另有两份可选文档放在仓库层面,不属于每个项目都有的那一组:[`CROSS-MACHINE.md`](CROSS-MACHINE.md)(全局者与工作者、或两个全局者分处不同机器时)和 [`channel-starter/`](channel-starter/)(没有共同仓库的项目之间用的专用信件信道仓库)。

### 前置条件

本仓库是一组模板和 shell helper,**建立在** [Claude Code](https://claude.com/claude-code) 命令行工具之上。Claude Code 只是两个角色共同的运行环境,角色背后用什么模型由你决定。本仓库不负责安装它,也不替代它。开始快速开始之前:

1. **已安装 Claude Code。** 按官方说明安装:<https://claude.com/claude-code>。自检:`claude --version` 能打印版本号。如果找不到 `claude`,`cc` 和 `cc-alt` 会报 `command not found`——而这是**最后**才失败的一步:source helper 和运行 `cc-init` 在没装 Claude Code 时都能成功,前面没有任何提示。
2. **每个角色一个模型,以及登录它的方式。** Claude 账号不是必须的。每个角色本质上就是一个指向某个模型端点的 `claude` 进程:
   - `cc`(全局者)用你默认的 `claude` 配置指向的模型——Claude 登录,或 `ANTHROPIC_*` 环境变量 / `settings.json`,见下面「使用 Claude 以外的模型」。
   - `cc-alt`(工作者)自带一个示例:DeepSeek 的 Anthropic 兼容端点,所以快速开始需要 `DEEPSEEK_API_KEY`。换别的端点就改 `cc-alt` 里的环境变量。
   - 两个角色都可以是非 Claude 模型。2026-10-15 核对过(Claude Code 2.1.300,Linux):在一个全新的 home 目录里、完全没有 Claude 登录,只设 `ANTHROPIC_BASE_URL`、`ANTHROPIC_AUTH_TOKEN` 和模型变量指向 DeepSeek 的 Anthropic 兼容端点,`claude -p` 正常返回,也没有生成凭据文件。**没有核对**:交互式的首次启动界面(print 模式会跳过它),以及其它端点。注意 Claude Code 自己的安装文档写的是需要 Claude 或 Console 账号、或受支持的云 provider——第三方 Anthropic 兼容端点现在能用,但不在文档承诺的范围内,将来可能变。
3. **Shell 与工具。** Linux / macOS:bash 和 git。Windows:PowerShell 加 Git for Windows——Git Bash 随它提供,安全预检脚本需要 bash。(Claude Code 本身不依赖 Git for Windows:没装时它退回用 PowerShell 执行命令。)Python 3 只有下面的可选部分才需要。
4. **Claude Code 版本。** 在 Claude Code 2.1.x 上开发和测试(最近一次核对:Linux 上 2.1.300)。只有跨会话通知有核实过的版本下限(见「让会话自己通知对方」);其余没有核实过下限,行为不对时先升级 Claude Code。

**核心与可选。** 快速开始装的是核心:模板、helper(`cc` / `cc-alt` / `cc-init`)和安全预检。下面这些是可选项,第一次跑可以全部跳过:

- **工作者权限守卫**(需要 Python 3)——见「工作者权限守卫」。
- **K10 第三者审查**(`k10-*.py`,Linux 快速开始第 6 步)——给比赛模式项目用的独立审查会话。值班脚本依赖 cron + flock,Windows 上没有配。
- **跨会话通知**——同机器上任意模型都能用;跨机器需要两端都有 Claude 账号(详见下文和 [`CROSS-MACHINE.md`](CROSS-MACHINE.md))。

#### 使用 Claude 以外的模型

在运行 `cc` 之前给全局者设好端点(或把同样的键放进 `cc` 读取的 `settings.json` 的 `env` 里):

```bash
export ANTHROPIC_BASE_URL="https://<你的端点>/anthropic"
export ANTHROPIC_AUTH_TOKEN="<你的 token>"     # 绝不能为空、绝不能不设——见下面的警告
export ANTHROPIC_MODEL="<你的模型名>"
# critic 子代理要的是 `haiku`,比赛模式要的是 `opus`。接非 Claude 端点时这些别名必须解析到你的端点真正提供的模型——
# `cc-alt` 对每一档都做了这件事,你也该做(比赛模式另外认 DUAL_MODEL_MODEL):
export ANTHROPIC_DEFAULT_OPUS_MODEL="<你的模型名>"
export ANTHROPIC_DEFAULT_SONNET_MODEL="<你的模型名>"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="<你的模型名>"
```

> **警告——`ANTHROPIC_BASE_URL` 指向非 Anthropic 主机时,token 绝不能留空或不设。** 2026-09-15 在 Claude Code 2.1.272 上实测:自定义 base URL 且没有 token 时,Claude Code 不报错,而是回落到本机的 Claude 登录,把该账号的 OAuth token 发给了这个自定义端点。`ANTHROPIC_AUTH_TOKEN=$VAR` 而 `$VAR` 为空走的是同一条路径;PowerShell 里给 `$env:X` 赋空串(等于删变量)也一样。`cc-alt` 会检查密钥非空并中止;你自己写的任何启动器都必须做同样的检查。机器上没有 Claude 登录就没有东西可泄露,但检查仍然建议保留。

会话之间的消息不取决于背后的模型:同机器上的 `SendMessage` 在两个都跑第三方端点的会话之间可用(作者的 VPS 上用 DeepSeek 会话实测过),Claude Code 官方文档(2026-09-18 核对)也把同机消息列为在所有 provider 上可用(≥ 2.1.248)。用 `/list-agents` 确认你的会话里有这个功能。设置 `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`、`DISABLE_TELEMETRY`、`DO_NOT_TRACK`、`DISABLE_GROWTHBOOK` 中任意一个,会让这个功能静默关闭(来自作者笔记,以 `/list-agents` 为准)。**跨机器**则不同:那条路需要两端都有 Claude 账号——见[让会话自己通知对方](#让会话自己通知对方)和 [`CROSS-MACHINE.md`](CROSS-MACHINE.md)。

### 仓库布局

```
templates/   # markdown 模板 —— 平台无关,两端共用
scripts/     # security-scan.sh —— bash,两端都能跑(Windows 走 Git Bash)
#              worker_guard.py + cc_allow_once.py + worker_guard_test.sh
#              dual-model-mode.sh —— 工作模式规则,启动器调用它
#              k10-watch.py / k10-stop-gate.py / k10-subagent-report.py —— 可选:第三者审查(K10)
#              tests/ —— bash test_dual_model_mode.sh ; bash test_k10.sh(测试套件只支持 Linux,未移植到 Windows)
docs/design/ # 设计记录(模板为什么这么写)
skills/      # allow-once —— 装进 ~/.claude/skills/
channel-starter/ # 可选:专用信件信道仓库的起步包(见 CROSS-MACHINE.md)
linux/       # bash helper(cc / cc-alt / cc-init)—— source 进 ~/.bashrc
windows/     # PowerShell helper(同名命令)—— dot-source 进 $PROFILE
```

只有 shell helper 按平台分开,其余(模板、安全扫描、许可证)都放仓库根共享。跨机器同步工作流更新:每台机器 `git pull` 即可,被 source 的 helper 文件原地更新。

两个移植版有一处真实的行为差异:**模型切换**。Linux 版在启动时用命令前缀环境变量注入 DeepSeek 端点;Windows 版用 `claude --settings ~\.claude\settings.deepseek.json` 传入。两种做法都只作用于单个会话,两个终端互不干扰。不要用"覆盖 `~\.claude\settings.json`"的方式切模型——那个文件被所有正在运行的 Claude Code 进程共享,改它会热重载到其它终端里已经在跑的会话上。详见各 helper 文件的头部注释。

### 快速开始 —— Linux / macOS(bash)

```bash
# 0. 前置条件(见上文)——这里打印「not found」就先停下
command -v git >/dev/null || echo "git not found"
command -v claude >/dev/null && claude --version || echo "claude not found —— 先安装 Claude Code(见前置条件)"

# 1. 克隆
git clone https://github.com/Haven16262/dual-model-workflow.git
cd dual-model-workflow

# 2. 把模板放到默认位置
mkdir -p ~/.dual-model/templates
cp -r templates/. ~/.dual-model/templates/
#   (尾部的 . 同时拷贝 .claude/ 等隐藏目录)
#   (或:export DUAL_MODEL_TEMPLATES=/绝对路径/dual-model-workflow/templates)

# 2b. 安装脚本:安全预检(全局者每次审查前运行)和工作模式规则(cc / cc-alt 读取)是核心;
#     k10-*.py 是可选的第三者审查钩子与值班,拷贝进去无副作用
mkdir -p ~/.claude/scripts
cp scripts/security-scan.sh scripts/dual-model-mode.sh scripts/k10-*.py ~/.claude/scripts/

# 3. 在 shell 配置里导出你的 DeepSeek key(绝不要提交进仓库)
echo 'export DEEPSEEK_API_KEY="sk-your-deepseek-key"' >> ~/.bashrc

# 4. 引入 helper
echo 'source '"$PWD"'/linux/dual-model.sh' >> ~/.bashrc
source ~/.bashrc

# 5. 在任意项目目录初始化工作流
cd /你的/项目
cc-init        # 复制 WORKFLOW.md + CLAUDE.md + context.md + .claude/{commands,agents,settings.json} + .workflow/

# 6. (可选,仅比赛模式的项目)排上 K9 值班 —— 见 WORKFLOW.md「K10 第三者」
#    */30 * * * * flock -n /tmp/k10-<项目>.lock ~/.claude/scripts/k10-watch.py /项目/路径 >> /日志/路径 2>&1
```

> **命名提醒:** `cc` 会在交互 shell 里覆盖系统 C 编译器(`/usr/bin/cc`)。如果你做 C 开发,改掉 `linux/dual-model.sh` 里的函数名(如 `dm`、`dm-ds`、`dm-init`)。

### 快速开始 —— Windows(PowerShell)

```powershell
# 0. 前置条件(见上文)
if (-not (Get-Command git -ErrorAction SilentlyContinue)) { Write-Host "git not found" }
if (Get-Command claude -ErrorAction SilentlyContinue) { claude --version } else { Write-Host "claude not found - 先安装 Claude Code(见前置条件)" }

# 1. 克隆
git clone https://github.com/Haven16262/dual-model-workflow.git
cd dual-model-workflow

# 2. 把模板放到默认位置
New-Item -ItemType Directory -Force "$env:USERPROFILE\.dual-model\templates" | Out-Null
Copy-Item -Recurse -Force templates\* "$env:USERPROFILE\.dual-model\templates\"
Copy-Item -Recurse -Force templates\.claude "$env:USERPROFILE\.dual-model\templates\"
Copy-Item -Recurse -Force templates\.workflow "$env:USERPROFILE\.dual-model\templates\"
#   (通配符不带隐藏目录,.claude/ 和 .workflow/ 要单独复制)
#   (或:$env:DUAL_MODEL_TEMPLATES = "C:\绝对路径\dual-model-workflow\templates")

# 2b. 安装安全预检脚本(在 Git Bash 下运行,Git Bash 随 Git for Windows 提供,Claude Code 并不自带)
New-Item -ItemType Directory -Force "$env:USERPROFILE\.claude\scripts" | Out-Null
Copy-Item scripts\security-scan.sh "$env:USERPROFILE\.claude\scripts\"
#     K10 钩子(可选,Python):钩子命令依次试 python3、python,只用真能跑起来的那个(Git Bash 里的 python3
#     可能是商店占位符);脚本强制 UTF-8 输入输出。2026-09-29 MSI 已测到字节层,CC 里端到端待测。
#     值班 k10-watch.py 依赖 cron + flock,Windows 上没有配。
Copy-Item scripts\k10-*.py "$env:USERPROFILE\.claude\scripts\"

# 3. 准备模型切换用的 settings(key 绝不要提交进仓库)
#    ~\.claude\settings.deepseek.json  — DeepSeek 端点 env + API key(工作者)
#    (全局者直接用你正常的 ~\.claude\settings.json,不用另外准备)

# 4. 在 PowerShell profile 里 dot-source helper
Add-Content $PROFILE ". `"$PWD\windows\dual-model.ps1`""
. $PROFILE

# 5. 在任意项目目录初始化工作流
cd C:\你的\项目
cc-init        # 复制 WORKFLOW.md + CLAUDE.md + context.md + .claude/{commands,agents,settings.json} + .workflow/
```

然后开两个终端:`cc` 跑全局者,`cc-alt` 跑工作者。各自会把角色静默注入系统提示(通过 `--append-system-prompt`,不作为聊天消息发送——第一条消息仍留给你说别的)并读 `WORKFLOW.md` / `context.md` 恢复状态。

选完角色后,脚本还会问一句**本轮话题**(可选,回车跳过)。它和机器标识、项目目录、角色一起构成会话名(通过 `--name`),格式四段:

```
<机器标识>-<项目目录名>-<角色>-<本轮话题>     # 例:vps-bili-overseer-登录态重构
<机器标识>-<项目目录名>-<角色>-<MMDD-HHMM>   # 回车跳过话题时的兜底,例:vps-bili-worker-0820-1145
```

四段各有各的用处,少一段都会出问题:

- **机器标识**——取自 `~/.claude/machine-tag`。**不是**给 AI 分辨机器用的(跨机器时对方显示的是自带主机名的 Remote Control 名字),是给**人**用的:同一个 git 仓库在两台机器上目录名相同,不加前缀的话 claude.ai 和手机的会话列表里会出现两条逐字相同的条目。该文件不存在时不加这一段。
- **项目目录名**——并行开两个项目时,固定叫 `worker` 会让交接消息投递到**另一个项目**的工作者那里,比没有自动化更糟。
- **角色**——同一项目里区分两个终端,交接消息靠它定向。
- **话题**——同一项目每次启动都重名的话,`/resume` 列表里会堆出一排一模一样的条目,你分不出哪个是哪次。`--name` 还会**覆盖** Claude Code 本来会自动生成的摘要标题,所以固定名字不只是没帮上忙,是把原本有用的标题换成了无用的。

代价是发送方不再能凭 cwd 算出对方的完整名字(话题是对方自己填的),发消息前要跑一次 `ListAgents` 按前缀找——见下一节。

### 切换角色

工作者完成一个阶段或遇到无法决策的问题,写入 `context.md` 后说「已写入 context.md,请切换到全局者」。你去全局者终端输入:

> 「工作者修改了内容,查看 context 文件」

全局者读取后给决策,写入 `context.md`,再说「决策已写入,可切换回工作者继续」。你去工作者终端输入:

> 「全局者修改了内容,查看 context 文件」

这两句话是切换信号,模型收到后会主动读 `context.md`,不需要你重新解释背景。

**Slash 命令简化:** 两句切换话语都有等价的 slash 命令(定义在 `templates/.claude/commands/`):

- 全局者终端:`/as-overseer` ≡ 「工作者修改了内容,查看 context 文件」(意:我现在接手全局者角色)
- 工作者终端:`/as-worker` ≡ 「全局者修改了内容,查看 context 文件」(意:我现在接手工作者角色)

(`as-` 而不是 `from-` 有两个理由:语义上"我现在是什么角色"比"来自谁"更直觉;键盘上 a/s 相邻,比 `from-` 起手 f→r 跨距小,输入更顺。)

语义相同,少打字。手打话语仍然有效。

### 让会话自己通知对方

上面那两步「你走到另一个终端敲字」可以省掉。Claude Code 支持跨会话消息(`SendMessage` + `ListAgents`),两个终端同时开着时,写完 `context.md` 的一方直接通知对方,对方按 `/as-worker` / `/as-overseer` 的完整流程接手。

版本门槛分两档:**macOS / Linux / WSL 2 需 ≥ 2.1.224,原生 Windows 需 ≥ 2.1.234**。用 `/list-agents`(别名 `/peers`)自查:命令本身不认识就是没有这个功能。

会话名的前三段(机器标识 + 项目目录 + 角色)发送方算得出,最后一段话题算不出。所以发消息前**跑一次 `ListAgents`**,找名字以 `vps-bili-worker-` 开头的那一行,按行里印的完整名字发送;**恰好一条**才发,零条或多条一律回退人工。这一次查询是流程的一部分,不是故障排查。

名字唯一时直接按名字投递,不再需要先带 `[ref]` 确认(2.1.232 起)。你自己也可以在 prompt 里打 `@` 加名字前几个字母,从候选里挑一个会话点名——省掉让模型先查一遍。

一条铁律:**消息只负责叫醒和指路,决策内容一律仍然写 `context.md`。**

> 这条不是洁癖。本工作流的核心承诺是「任何一方新开 session 都能只靠文件还原完整决策链」;消息是易失的,不进文件就等于没发生过。一旦决策开始走消息,承诺立刻作废,而且失效得悄无声息——当下能跑,回头追溯时才发现断链。

发送失败(对方没开终端、名字对不上、版本或平台不支持)时,**回退到人工中转,不重试**。所以这是可选加速,不是新的必经路径:自动通道断了,工作流退化成原来的样子,照常运转。

**可选:让平台替你盯着。** 全局者交出任务时可以带上 `notify_when_idle`(≥ 2.1.236,仅同机器),请平台在工作者下次空闲时回一条通知。好处是不依赖工作者记得发消息;代价是它只说「空闲了」,不说「交接好了」——收到后仍要读 `context.md` 确认有没有新交接块。

**平台状态:** 跨会话消息最初只有 macOS 和 Linux,Windows 从 2.1.234 起补齐,现在三端都可用。`windows/dual-model.ps1` 已跟进会话命名,本节对 Windows 同样生效。模板不为平台分叉,两端行为一致——只有非 ASCII 目录名的哈希兜底实现不同(Linux 用 `cksum`,PowerShell 没有,改用 SHA256 前 8 位十六进制),两边都只保证「同路径永远同结果」,不保证跨平台算出同一个值。

同机器上两个终端直接走本地 socket(Windows 上是命名管道),不经过 Anthropic 服务器;**跨机器**(比如 VPS 和本地电脑)才需要两端都登录 Claude 账号并连上 Remote Control,消息经 Anthropic 服务器中转。没有 Claude 账号这条路就走不通——交接里「共享仓库」那一半照旧,只是那条一句话的指针消息要靠别的渠道送(聊天、邮件、webhook、别的开源消息工具,或自己搭的东西),见 [`CROSS-MACHINE.md`](CROSS-MACHINE.md)。另外 WSL 2 里的会话和同一台电脑上的原生 Windows 会话**互相看不见**——注册在不同的 home 目录,socket 类型也不同。

跨机器该怎么组织工作流——用共享 git 仓库当交接介质、寻址方式的差异、Linux ↔ Windows 的换行符/路径/时区坑——单独写在 [`CROSS-MACHINE.md`](CROSS-MACHINE.md)。同机使用不需要读。

> **测试时的坑:** 从一个 Claude Code 会话里 spawn 出来的终端会继承 `CLAUDE_CODE_CHILD_SESSION` 环境变量,那个会话**不会注册进 peer 列表**,`ListAgents` 里根本看不见(终端里会提示 `Transcript saving is off — inherited CLAUDE_CODE_CHILD_SESSION marker`)。真人在干净终端里敲 `cc` 不会遇到,但脚本化验证这套机制时会栽进去,而且现象和"名字对不上"一模一样。

**别指望它做无人值守自动循环。** 发给「已跳过权限确认」会话的跨会话消息会被扣住等人工批准(平台设计如此)。这套机制省的是打字和上下文切换,不省盯着——这跟本工作流「人是检查点」的前提是一致的。

### 工作者权限守卫

> **默认不装,完全可选。** 本仓库不会自动安装守卫,也不自带任何权限规则(`allow` / `ask` / `deny`)——下文提到的 `ask` 规则来自作者个人的 `settings.json`,不在仓库里。不装守卫的话,工作者按你已有的权限配置运行,没有任何东西拦它执行 `git push`:「工作者不推送」这条规则此时只是 `WORKFLOW.md` 里的文字。不想要守卫?跳过本节,并删除 `scripts/worker_guard.py`、`scripts/cc_allow_once.py`、`scripts/worker_guard_test.sh` 和 `skills/allow-once/`。想要?照下面的安装步骤做就行。`WORKFLOW.md` 模板里有一节「命令被守卫拦下时」是以装了守卫为前提写的——不装守卫就忽略或删掉它。

工作者会话**连不上 Remote Control**：`cc-alt` 把 `ANTHROPIC_BASE_URL` 指向本地网关，而 Claude Code 在这个变量指向 `api.anthropic.com` 以外的主机时一律拒绝 Remote Control。同时权限弹窗**永不超时**。两条叠起来：你不在工位时工作者撞上弹窗，不是"等一会儿"，是无限期挂死。(Remote Control 本身需要 Claude 账号;没有账号时任何会话都用不了它,弹窗没人答照样挂死。)

守卫是个 `PreToolUse` 钩子，在弹窗打开**之前**把这些命令拒掉——「跳过去做别的」这个选项只有这样才存在。

| 类别 | 命令 | 行为 |
|---|---|---|
| 硬拒 | `git push` | 没有放行通道。工作者提交、记录状态、交接给全局者，由全局者复审后自行发布 |
| 拒 + 窗口 | `ssh`、`chmod` | 自动入队。你敲 `/allow-once` 开 10 分钟窗口，工作者重试，正常弹窗照常出现 |

拦截集合刻意与**参考配置**的 `settings.json` 里那三条 `ask` 规则对齐（`chmod` / `ssh` / `git push`）——在那台机器上它们是工作者唯一会撞上的弹窗来源。**你的机器可能一条 `ask` 规则都没有**，那时这些命令在非 auto 模式下走默认弹窗流程照样会弹，而守卫就成了工作者与「没人能答的对话框」之间唯一的东西。别默认两边的清单对得上，先查自己的规则。

两条值得写明的性质：

* **开窗不等于授权。** 它只让弹窗能弹出来，权限仍然来自你在弹窗上点的那一下。
* **模型不能给自己开窗。** `allow-once` skill 设了 `disable-model-invocation: true`，其 `!` 行在展开阶段执行、早于模型看到任何内容——开窗在结构上就是人的动作。

安装（两端通用，脚本是 Python 不是 shell）：

```bash
cp scripts/worker_guard.py scripts/cc_allow_once.py ~/.claude/scripts/
mkdir -p ~/.claude/skills/allow-once && cp skills/allow-once/SKILL.md ~/.claude/skills/allow-once/
echo vps > ~/.claude/machine-tag        # 或 msi / n1 …… 每台机器一个短标识
```

然后把钩子加进**只有工作者加载**的那个设置文件（`~/.claude/settings.deepseek.json`），**绝不要加进 `settings.json`**——全局者必须保留它的正常弹窗，因为(有 Claude 账号时)它才是能经 Remote Control 推到你手机的那个会话：

```json
{ "matcher": "Bash",
  "hooks": [{ "type": "command",
              "command": "python3 -S \"$HOME/.claude/scripts/worker_guard.py\"",
              "timeout": 10 }] }
```

Windows 上钩子命令和 `SKILL.md` 里都要**写解释器的完整路径**，例如 `E:/Anaconda/python.exe`。不要因为 `python3` 能解析就认为它可用：默认 Windows 装机环境里 `python3` 是微软商店的占位符，**在 PATH 上但不是解释器**，退出码 9009 并提示 *"Python was not found"*。钩子指向它就会失败，而失败的钩子是**失败放行**的钩子。裸 `python` 在 Git Bash 里可能好用，从钩子里却未必——钩子执行时的 PATH 不是 Bash 那份。

`SKILL.md` 里解释器出现**两次**——`allowed-tools` 里一次，`!` 行里一次——两处必须**逐字一致**。Claude Code 会拿注入的命令去比对规则，比对结果不是 `allow` 就**中止整个调用**：改了一处漏了另一处，不是让 skill 变差，是让它彻底失效。

**编码同样是个坑。** 这两个脚本在代码里把 `sys.stdout` 定死成 UTF-8，而不是靠钩子命令写 `-X utf8`：Claude Code 按 UTF-8 解析钩子 stdout，而 Python 默认走 locale 编码（简中 Windows 是 cp936）。一旦错开，JSON 解析失败、`permissionDecision` 丢失、命令照常执行。**失败放行的守卫比没有守卫更危险**——它让人以为 `git push` 被挡住了，其实没有。测试套件里有专门一条查这个，别跳过。

**Linux 用户注意确认 `cc-alt` 真的传了这个文件。** Linux 侧端点走环境变量，`settings.deepseek.json` 是可选的、很容易漏——而钩子写在一个没人加载的文件里是**静默失效**，不会报错。`linux/dual-model.sh` 里的 helper 在文件存在时会传；如果你 source 的是这个功能之前的旧副本，重新 source 一次。

装完验证：

```bash
bash scripts/worker_guard_test.sh          # 或: bash scripts/worker_guard_test.sh python
```

22 条分类用例，其中包括催生这个解析器的那几条：`git log --grep push`、以及 heredoc 正文里写着 `git push` 例子的情况，**都不能**被拦——硬拒路径没有逃生舱，误伤会把工作者卡死在一条无害命令上。

### 触发切换的条件(工作者 → 全局者)

工作者遇到以下情况必须停下切换到全局者:

1. 出现架构方向分歧,有多个方案无法判断选哪个。
2. 遇到安全、性能相关的设计决策。
3. 完成一个完整模块,需要确认方向再继续。
4. 连续两次尝试仍无法解决某个问题。

条件 4 很重要 —— 与其让工作者反复试错消耗 token,不如切到全局者换个思路。

### 审查机制 —— 以及为什么

早期版本有个藏得很深的问题:**全局者名义上要「阶段性审查工作者输出」,但实际上它根本没在审查。**

问题出在写入格式。工作者完成后只写「完成情况」和「任务进度」—— 全是结果(做完了什么),没有决策(怎么做的、动了什么)。全局者拿着结果摘要,无从判断方向有没有偏、有没有踩安全坑,审查只能停在「看起来做完了」的表面。

修法不是让全局者去读全部代码(那违背它「不读大量文件」的原则),而是让工作者在交付时主动暴露关键决策。工作者写入格式现在带四项强制清单:

```
**关键决策点:**(每项必须显式回答,无则写「无」,不留空)
- 架构/接口变动:...
- 安全相关:是否涉及 认证/密钥/用户输入/SQL/文件路径/外部请求
- 偏离原计划:...
- 未解决的疑虑:继续推进但没把握的点
```

这里有意把**事实上报**和**风险判断**分开:工作者只需如实回答「改没改接口」「碰没碰这些安全敏感面」—— 即使不懂风险也答得出;风险判断交给全局者。其中「未解决的疑虑」是单条价值最高的一项,专门抓那种**工作者没卡住、所以从不触发切换、但其实心里没底**的盲区 —— 这种情况以前完全漏在网外。

配套给全局者加一条硬规则:**只要安全项非空,就必须 invoke `critic` 子代理**(定义在 [`templates/.claude/agents/critic.md`](templates/.claude/agents/critic.md),用 Haiku 跑)去读相关文件并返回结构化审查报告,不能只看摘要。这把"必须读代码"规则操作化了 —— 全局者自己仍不读大量文件,由 critic 子代理代读并出报告,全局者凭报告判断。

但这仍留了一个缺口:逃生口的开关挂在工作者自报上,而模型会反射性填「无」(见下面的告诫)。对策是加一层不依赖自报的客观触发器:全局者每次审查前先跑 [`scripts/security-scan.sh`](scripts/security-scan.sh) —— 纯本地 `grep` 扫 diff 新增行(零 token、不调模型),命中认证/密钥、SQL、命令执行、路径穿越、外部请求等安全敏感关键词就报警。**脚本命中或安全项非空,二者任一,都强制走 `critic` 子代理审查。**命中不等于真有问题,只是把审查从"可选"升级为"必须",脚本给的是触发信号,不是结论。

### 这个补丁不会自动生效(诚实的告诫)

得诚实说一点:整套机制押在工作者**自报诚实**上,而工作者是更小/更便宜的模型。模型有个倾向 —— 为尽快收尾把四项反射性全填「无」,尤其「未解决的疑虑」(承认不确定恰恰是模型最不愿做的)。一旦它在安全项该填却填了「无」,前面那个「安全项非空→必读代码」的逃生口就被空填绕过,整套机制空转。

所以对策不在再改格式,而在全局者的行为:**与某个工作者模型协作的早期,即使它安全项写「无」,也要拿实际 diff 抽查一两次**,先摸清这个工作者到底是诚实自报还是反射填「无」,据此校准对清单的信任度,而不是默认全信。机制设计能做的到此为止,剩下的得靠实跑校准。

### context.md 写入格式

权威的可复制格式(全局者写入、工作者写入、工作者→全局者交接)见 [`templates/WORKFLOW.md`](templates/WORKFLOW.md)。格式统一后,任何一方开启新 session 都能通过历史记录还原完整决策链,不会出现「不知道上次为什么这么做」。

### 相关工作

把 AI 编码工作拆给一个强"规划者 / 架构师"模型 + 一个弱 / 更便宜的"执行者"模型,这个模式有大量先例。本仓库只是其中一种特定实现,不是新颖设计。值得知道的 prior art(每一项的现状均于 2026-10-15 对照 GitHub 核对过):

**成熟框架:**
- [aider](https://github.com/Aider-AI/aider) —— `--architect` 模式在单一 CLI 内把规划者模型和编辑者模型配对。是本仓库思路最直接的概念父本。仍在维护(最近提交 2026-05-22),该选项仍在其参数列表里。
- [MetaGPT](https://github.com/FoundationAgents/MetaGPT)(已从 `geekan/MetaGPT` 迁移)、[CrewAI](https://github.com/crewAIInc/crewAI)、[LangGraph](https://github.com/langchain-ai/langgraph) —— 多 agent 框架,角色化编排,规划者 / 执行者是它们支持的经典分工之一。CrewAI 和 LangGraph 开发活跃;MetaGPT 最近一次提交是 2026-01-21。
- [AutoGen](https://github.com/microsoft/autogen) —— 现已进入**维护模式**:不再加新功能,由社区维护。它的 README 把新用户引向继任者 [Microsoft Agent Framework](https://github.com/microsoft/agent-framework)。
- [cline](https://github.com/cline/cline) —— IDE 内嵌的 agent,带 Plan / Act 模式分离;开发活跃,现在也提供 SDK 和 CLI 形态。[Roo Code](https://github.com/RooCodeInc/Roo-Code)(原 `RooVetGit/Roo-Cline`)已被**归档**(只读);最后一个版本是 2026-05-15 的 v3.54.0。

**直接重叠的小仓库**(创建于 2026 年 3 月到 5 月之间,早于本仓库;本仓库创建于 2026-05-19):
- [chewwwwwwwwww/claude-codex-hybrid-kit](https://github.com/chewwwwwwwwww/claude-codex-hybrid-kit) —— Claude Code 和 Codex 通过每个 issue 一个 Markdown 文件(`issue-N.md`)作总线分工,由显式 slash commands 驱动(`/scope → /architect → /build → /review → /verify`):Claude 负责定范围、实现和验证,Codex 负责架构和审查,每一步由人手动触发。用 Codex 而非 DeepSeek,把流程固定成流水线。体量很小(2 star);最近提交 2026-04-27。
- [SelimCakil/claude-deepseek-architect](https://github.com/SelimCakil/claude-deepseek-architect) —— Claude 当架构师,DeepSeek、Kimi、Gemini 当开发者:独立的部分经按供应商划分的启动器配置(各自独立的 Claude Code 配置目录)并行派发,另有一个可选的 MCP 服务器(houtini-lm)做文本交接。派发是自动的,不是人介入切换。README 是土耳其语。最近提交 2026-07-22。
- [evan-e2438927/sdlc-workflow](https://github.com/evan-e2438927/sdlc-workflow) —— 偏重的 SDLC 流水线,以 Claude Code 和 Codex 的 skill 插件形式提供:Claude Code 写,Codex CLI 在形式化门禁处审查,浏览器自动化验证(`proposal → apply → qa → accept → pr`),一条命令(`doit`)可把所有阶段串到提 PR。27 star;最近提交 2026-09-26。

**2026-10-15 在 GitHub 搜索中另外看到的**——只依据各仓库自己的一句话简介判断,没有细看也没有试用:
- [tristanMatthias/bot2bot](https://github.com/tristanMatthias/bot2bot) —— 多个 Claude Code 会话之间的协调,面向"overseer / worker"场景。
- [joancarvajal80/sfcrew](https://github.com/joancarvajal80/sfcrew) —— Claude Code 当架构师,加上无界面的 DeepSeek / GLM / Claude 执行器,通过 `tasks.csv` 协调。
- [aravindhsampath/agentic-template](https://github.com/aravindhsampath/agentic-template) —— 项目模板,带架构师和工程师子代理,以及多模型代码审查(DeepSeek + Kimi)。

**本仓库的差异点(小,但真实):**
- **人介入切换 + 显式触发话语**,而非程序化派发(claude-deepseek-architect 和 sdlc-workflow 的 `doit` 属于后者)。claude-codex-hybrid-kit 同样是人手动触发,所以这一点不是独有的;本仓库的不同在于共享状态是每个项目一份仅追加的 `context.md`,而不是每个 issue 一个文件。代价是慢,好处是透明、零额外依赖——只要有 Claude Code 就能跑。
- **四项「关键决策点」清单**,工作者每次交付强制填,事实上报与风险判断分离。
- **关于清单为何不自动生效的诚实告诫**——工作者模型可能反射性填「无」,全局者需要抽查 diff 校准信任度。我在上面列出的仓库的 README 里没有找到对这条局限的讨论(2026-10-15 核对,仅读了 README)。

如果你想要更自动化 / 更重型的方案,优先选 aider 的 architect 模式或上述仍在积极维护的多 agent 框架。本仓库面向的场景是:你想要双模型分工,但不想引入 Claude Code 之外的任何额外依赖。

### 许可证

MIT —— 见 [LICENSE](LICENSE)。
