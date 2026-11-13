# Workflow diagrams

> 中文版：[diagrams.md](diagrams.md)

> This page holds diagrams only. The rules live in [`templates/WORKFLOW.md`](../templates/WORKFLOW.md); if a diagram disagrees with it, fix the diagram.
> The diagrams deliberately state no file counts and no version numbers — numbers like that drift. For the list of files, see the "file roles" table in WORKFLOW.md.

## Overview: start here

Two models each own one half of the job and hand off through a shared file, not through chat history. The diagrams below expand this: who reads and writes which file, what is checked each round, and the full sequence of one handoff.

```mermaid
%%{init: {"flowchart": {"padding": 16}}}%%
flowchart LR
    O["Overseer<br/>sets direction · decides · reviews"]
    CTX[("context.md<br/>shared handoff file")]
    W["Worker<br/>writes code · iterates · commits"]

    O -->|"1. write decisions and tasks"| CTX
    CTX -->|"2. read tasks, start work"| W
    W -->|"3. commit code, write handoff"| CTX
    CTX -->|"4. read handoff, review and approve"| O

    classDef overseer fill:#dbeafe,stroke:#2563eb,color:#1f2328
    classDef worker fill:#dcfce7,stroke:#16a34a,color:#1f2328
    classDef file fill:#fef9c3,stroke:#ca8a04,color:#1f2328
    classDef script fill:#f1f5f9,stroke:#64748b,color:#1f2328
    classDef third fill:#f3e8ff,stroke:#9333ea,color:#1f2328
    classDef user fill:#ffffff,stroke:#334155,color:#1f2328
    class O overseer
    class W worker
    class CTX file
```

- **Why split the roles:** one model working for long enough runs out of context and starts to blur roles. Two models, each doing only what it is good at, avoid that.
- **Why go through a file:** messages between the two sessions only wake the other side up; every decision is written into `context.md`, so a fresh session on either side can pick up from the files alone.

## Diagram 1a: core — two roles, shared files, commits

Solid arrow = write or run; dashed arrow = read or notify; double-headed arrow = read and write.

Colors: blue = Overseer, green = Worker, yellow = files, grey = scripts and checks, purple = third-party reviewers.

```mermaid
%%{init: {"flowchart": {"padding": 16}}}%%
flowchart LR
    User(["User<br/>opens two terminals, switches roles"])

    O["Overseer<br/>direction · decisions · review · archiving<br/>implements high-risk modules itself"]
    W["Worker<br/>execution · iteration · commits<br/>never pushes"]

    CTX[("context.md<br/>Current State · cross-phase conventions<br/>this phase's history")]
    OWN["WORKFLOW.md · docs/<br/>(both read; the Worker may also write docs/)"]
    HIST["context_history.md<br/>(Overseer archives and looks back)"]
    SES["sessions-md.py<br/>writes the sessions.md registry"]
    GIT[("git repository")]

    User -- "/as-overseer" --> O
    User -- "/as-worker" --> W

    O <-->|"read; write: Current State, decisions, conventions"| CTX
    W <-->|"read; write: handoff block<br/>backlog and unverified premises are append-only"| CTX
    O -->|"maintains"| OWN
    O -->|"archives when a phase closes"| HIST
    W -.->|read| OWN

    W -->|"commit first, then write the handoff"| GIT
    O -.->|"reviews by sha; approves up to a sha"| GIT

    O -->|"every handoff --note"| SES
    W -->|"every handoff --note"| SES

    O <-.->|"wake-up (optional speed-up): points the way, carries no decisions"| W

    classDef overseer fill:#dbeafe,stroke:#2563eb,color:#1f2328
    classDef worker fill:#dcfce7,stroke:#16a34a,color:#1f2328
    classDef file fill:#fef9c3,stroke:#ca8a04,color:#1f2328
    classDef script fill:#f1f5f9,stroke:#64748b,color:#1f2328
    classDef third fill:#f3e8ff,stroke:#9333ea,color:#1f2328
    classDef user fill:#ffffff,stroke:#334155,color:#1f2328
    class User user
    class O overseer
    class W worker
    class CTX,OWN,HIST,GIT file
    class SES script
```

### Diagram 1a: what to take away

- **Files are the only carrier of decisions.** Messages between the two sessions only wake the other side up and point the way; every decision is written into `context.md` first, so a fresh session on either side can reconstruct the decision chain from the files alone.
- **The Worker commits but never pushes.** Publishing is decided by the Overseer after review; what gets approved is a real commit, recorded in `context.md` as "approved up to sha".
- **`sessions.md` is not a decision carrier.** It is a session list for humans, written by a script; each role only supplies its own line through `--note`.

## Diagram 1b: the Overseer's checks each round, and third-party reviewers

The upper half is the set of checks present in every mode; the lower half is the automatic trigger machinery for third-party reviewers (competition mode). Outside competition mode, the Overseer can still summon a skeptic by hand for architecture decisions.

```mermaid
%%{init: {"flowchart": {"padding": 16}}}%%
flowchart LR
    O["Overseer"]

    subgraph EVERY["Every round (all modes)"]
        direction TB
        S1["security-scan.sh<br/>scans base..HEAD and the work tree, zero tokens"]
        S2["ctx-size.py · ctx-pointers.py<br/>length, dangling pointers"]
        S3["sessions-md.py --dry-run<br/>count of empty notes"]
    end

    COND{"Security review required?<br/>scan rc=1, or rc=2 that can't be fixed<br/>Worker's 'security-relevant' field non-empty<br/>first round of a project"}
    CRITIC["critic subagent<br/>read-only security review<br/>falls back to the built-in security-reviewer"]

    subgraph COMP["Automatic third-party triggers (competition mode, optional)"]
        direction TB
        WATCH["k10-watch.py<br/>cron watch: K9 criteria + calendar"]
        TP["skeptic · proposer · reproducer<br/>independent claude -p sessions"]
        REP[(".workflow/reports/<br/>report originals")]
    end

    GATE["Stop hook k10-stop-gate.py (competition mode)<br/>checks format only: every opinion number has a response line"]

    O --> EVERY
    S1 --> COND
    COND -- "yes" --> CRITIC
    CRITIC -- "report" --> O

    WATCH -->|launches| TP
    TP -->|writes to disk| REP
    WATCH -. "notifies" .-> O
    O -. "reads via --check" .-> REP
    GATE -. "checked when the turn ends" .-> O

    classDef overseer fill:#dbeafe,stroke:#2563eb,color:#1f2328
    classDef worker fill:#dcfce7,stroke:#16a34a,color:#1f2328
    classDef file fill:#fef9c3,stroke:#ca8a04,color:#1f2328
    classDef script fill:#f1f5f9,stroke:#64748b,color:#1f2328
    classDef third fill:#f3e8ff,stroke:#9333ea,color:#1f2328
    classDef user fill:#ffffff,stroke:#334155,color:#1f2328
    class O overseer
    class S1,S2,S3,COND,CRITIC script
    class WATCH,TP,GATE third
    class REP file
    style EVERY fill:#f8fafc,stroke:#94a3b8,stroke-dasharray:4 4
    style COMP fill:#faf5ff,stroke:#c084fc,stroke-dasharray:4 4
```

### Diagram 1b: what to take away

- **Security review does not rely on self-reporting alone.** A scan hit forces it even when the Worker wrote "none" under security; conversely, a non-empty self-report triggers it too.
- **critic is available in every mode** and is a verifier-type subagent; only the `k10-watch.py` watch and the Stop hook are limited to competition mode.
- **The Stop hook checks format only, and only when the Overseer ends its turn:** with no response, it blocks. A single line "S1 S2 S3 accepted" satisfies it, and it does not guarantee the responses were written with care.

## Diagram 2: sequence of one handoff (the Worker finishes a module)

This is the most common round: the Worker finishes a complete module and hands it to the Overseer, who reviews it, then either approves or sends it back, and gives the next step. Other reasons to switch (a disagreement on direction, a contradictory spec, a broken premise, and so on) follow the same "write the file first, then wake the other side" order; only the handoff block's format and the Overseer's handling differ — see "switch trigger conditions" in WORKFLOW.md.

```mermaid
sequenceDiagram
    autonumber
    participant W as Worker
    participant G as git repository
    participant C as context.md
    participant O as Overseer
    participant S as security-scan.sh
    participant K as critic subagent

    Note over W: Read WORKFLOW.md and context.md<br/>work through the task list in Current State
    Note over W: Re-run the gates, record rc (when there are gates)
    W->>G: Commit this round's changes (when there are changes, commit only, never push)
    opt This round found something new or relied on an unverified premise
        W->>C: Step 1: append to backlog and unverified premises
    end
    W->>C: Step 2: append the handoff block (sha, key decision points, gate results, spec corrections)
    Note over W: Register in sessions.md
    Note over W,O: The wake-up sentence is fixed, and run ListAgents first to look up the peer's name<br/>Worker to Overseer: written to context.md handoff block, please take over per /as-overseer<br/>Overseer to Worker: decisions written to context.md, please take over per /as-worker<br/>If it cannot be sent, fall back: the user types /as-overseer or /as-worker in the other terminal
    W-->>O: wake-up

    Note over O: Read WORKFLOW.md and context.md<br/>run the length, dangling-pointer and sessions.md checks
    O->>S: Scan base..HEAD and the work tree
    S-->>O: rc: 0 no hit / 1 hit / 2 did not run
    Note over O: Restate the latest handoff to the user, always including the scan rc
    O->>G: Check that the sha is a real commit and an ancestor of HEAD
    alt Files changed but no valid sha
        Note over O: Commit missing, not a commit, not an ancestor of HEAD<br/>or files claimed as changed are still uncommitted<br/>(registering and waking on a send-back follow from "register on every handoff")
        O->>C: Write the send-back decision: commit first, no approval this round
        Note over O: Register in sessions.md
        O-->>W: wake-up
    else Valid sha, or "commit: none" with no changes confirmed
        Note over O: Check the key decision points and gate results<br/>for quality items no tool judges, read the output yourself<br/>never approve on the Worker's self-report
        opt rc=1, or rc=2 that can't be fixed, or 'security-relevant' non-empty, or first round
            O->>K: Structured review of the named files (read-only)
            K-->>O: Review report
        end
        alt Review passes, no gate regression
            O->>C: Overwrite the rotating part of Current State, append the decision, write "approved up to sha"
            Note over O: Register in sessions.md
            O-->>W: wake-up
        else Regression, or the review asks for changes
            O->>C: Write the decision and required changes, without "approved up to"
            Note over O: Register in sessions.md
            O-->>W: wake-up
        end
    end
```

### Diagram 2: what to take away

- **The order cannot change: commit, then write the file, then wake the other side.** The handoff block records the sha of this round's commit; the wake-up message carries no decisions and only points the way.
- **The scan runs before the sha check, unconditionally, every round.** The send-back branch already has the scan result.
- **Approval is only given after a passing review.** With a gate regression, or when the review asks for changes, the Overseer writes only the decision and the required changes, and does not write "approved up to".
- **What the Overseer approves is a real commit.** "Approved up to sha" goes into `context.md` and becomes the base of the next round's scan, so uncommitted changes in the work tree cannot be approved.
- **Several details are left out of the diagram**; see WORKFLOW.md: checking the five mandatory-escalation categories when architecture or interfaces change, when re-runnable gates are re-run, and how critic gets registered when the session starts outside the project directory.
