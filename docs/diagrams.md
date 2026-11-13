# 工作关系图

> English version: [diagrams.en.md](diagrams.en.md)

> 这页只放图。规则以 [`templates/WORKFLOW.md`](../templates/WORKFLOW.md) 为准，图和它冲突时改图。
> 图里不写文件总数、不写版本号：这类数字会漂，文件清单看 WORKFLOW.md 的「文件分工」表。

## 概览：先看这张

两个模型各管一摊事，靠一份共享文件交接，不靠聊天记录。下面几张图是展开：谁读写哪些文件、每轮检查什么、一次交接的完整顺序。

```mermaid
%%{init: {"flowchart": {"padding": 16}}}%%
flowchart LR
    O["全局者<br/>定方向 · 做决策 · 审查"]
    CTX[("context.md<br/>共享的交接文件")]
    W["工作者<br/>写代码 · 迭代 · 提交"]

    O -->|"① 写下决策和任务"| CTX
    CTX -->|"② 读任务，开工"| W
    W -->|"③ 提交代码，写交接"| CTX
    CTX -->|"④ 读交接，复审并放行"| O

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

- **为什么这样分：** 一个模型做到最后，上下文会耗尽、角色会混。拆成两个，各自只做擅长的事。
- **为什么走文件：** 两个会话之间的消息只负责叫醒；决策一律写进 `context.md`，任何一方新开会话，只读文件就能接上。

## 图 1a：核心——两个角色、共享文件、提交

实线 = 写或执行；虚线 = 读或通知；双向箭头 = 又读又写。

颜色：蓝 = 全局者，绿 = 工作者，黄 = 文件，灰 = 脚本与检查，紫 = 第三者。

```mermaid
%%{init: {"flowchart": {"padding": 16}}}%%
flowchart LR
    User(["用户<br/>开两个终端，切换角色"])

    O["全局者 Overseer<br/>方向 · 决策 · 审查 · 归档<br/>高风险模块由它直接实现"]
    W["工作者 Worker<br/>执行 · 迭代 · 提交<br/>不 push"]

    CTX[("context.md<br/>当前状态 · 跨 Phase 约定<br/>本 Phase 历史")]
    OWN["WORKFLOW.md · docs/<br/>（双方读；docs/ 工作者也可写）"]
    HIST["context_history.md<br/>（全局者归档、回溯）"]
    SES["sessions-md.py<br/>写 sessions.md 会话注册表"]
    GIT[("git 仓库")]

    User -- "/as-overseer" --> O
    User -- "/as-worker" --> W

    O <-->|"读；写：当前状态、决策、约定"| CTX
    W <-->|"读；写：交接块<br/>backlog 与未验证的前提只追加"| CTX
    O -->|"维护"| OWN
    O -->|"phase 关闭时归档"| HIST
    W -.->|读| OWN

    W -->|"先提交，再写交接块"| GIT
    O -.->|"按 sha 复审；放行到 sha"| GIT

    O -->|"每次交接 --note"| SES
    W -->|"每次交接 --note"| SES

    O <-.->|"叫醒（可选加速）：只指路，不带决策内容"| W

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

### 图 1a 读图要点

- **文件是唯一的决策载体。** 两个会话之间的消息只负责叫醒、指路；任何决策都先写进 `context.md`，所以任何一方新开会话，只读文件就能还原决策链。
- **工作者只提交、不 push。** 发布由全局者复审后决定；放行的是一个真实提交，写成「放行到 sha」记进 `context.md`。
- **`sessions.md` 不是决策载体。** 它是给人查的会话清单，由脚本写，角色只通过 `--note` 提供自己那一行。

## 图 1b：全局者每轮的检查，以及第三者

上半是每个模式都有的检查；下半是比赛模式的第三者自动触发机制（非比赛模式下，架构决策时也可以手动召唤质疑者）。

```mermaid
%%{init: {"flowchart": {"padding": 16}}}%%
flowchart LR
    O["全局者 Overseer"]

    subgraph EVERY["每轮必跑（所有模式）"]
        direction TB
        S1["security-scan.sh<br/>扫 base..HEAD 和工作树，零 token"]
        S2["ctx-size.py · ctx-pointers.py<br/>长度、悬空指针"]
        S3["sessions-md.py --dry-run<br/>空备注数"]
    end

    COND{"必须做安全审查吗？<br/>扫描 rc=1，或 rc=2 修不好<br/>工作者「安全相关」非空<br/>项目首轮"}
    CRITIC["critic 子代理<br/>只读安全审查<br/>不可用时退用内置 security-reviewer"]

    subgraph COMP["第三者的自动触发（比赛模式，可选）"]
        direction TB
        WATCH["k10-watch.py<br/>cron 值班：K9 判据 + 日历"]
        TP["质疑者 · 提出者 · 复现者<br/>独立的 claude -p 会话"]
        REP[(".workflow/reports/<br/>报告原文")]
    end

    GATE["Stop 钩子 k10-stop-gate.py（比赛模式）<br/>只查格式：每个意见编号有一行表态"]

    O --> EVERY
    S1 --> COND
    COND -- "是" --> CRITIC
    CRITIC -- "报告" --> O

    WATCH -->|启动| TP
    TP -->|落盘| REP
    WATCH -. "通知" .-> O
    O -. "--check 读" .-> REP
    GATE -. "结束回合时检查" .-> O

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

### 图 1b 读图要点

- **安全审查不只靠自报。** 脚本命中也强制触发，即使工作者在「安全相关」写了「无」；反过来，自报非空同样触发。
- **critic 在所有模式下都可用**，是验证者类的子代理；只有 `k10-watch.py` 的值班和 Stop 钩子限于比赛模式。
- **Stop 钩子只管格式，且在全局者结束回合时才检查：** 没有回应就拦下。一行「S1 S2 S3 接受」就能满足它，不保证回应是认真写的。

## 图 2：一轮交接的时序（工作者完成一个模块）

这是最常见的一轮：工作者做完一个完整模块，交给全局者审查，全局者审查后放行或退回，并给出下一步。其他切换原因（方向分歧、spec 矛盾、前提不成立等）走同样的「先写文件、再叫醒」顺序，只是交接块的格式和全局者的处理不同，见 WORKFLOW.md「切换触发条件」。

```mermaid
sequenceDiagram
    autonumber
    participant W as 工作者
    participant G as git 仓库
    participant C as context.md
    participant O as 全局者
    participant S as security-scan.sh
    participant K as critic 子代理

    Note over W: 读 WORKFLOW.md 与 context.md<br/>按「当前状态」里的任务清单执行
    Note over W: 重跑闸门，记 rc（有闸门项时）
    W->>G: 提交本轮改动（有改动时；只提交，不 push）
    opt 本轮有新发现或未核实的前提
        W->>C: 第一步：backlog、未验证的前提只追加
    end
    W->>C: 第二步：追加交接块（sha、关键决策点、闸门结果、spec 修正）
    Note over W: 登记 sessions.md
    Note over W,O: 叫醒句固定，发送前先 ListAgents 查对方名字<br/>工作者→全局者：已写入 context.md 交接块，请按 /as-overseer 流程接手<br/>全局者→工作者：决策已写入 context.md，请按 /as-worker 流程接手<br/>发不出去就回退：用户在另一个终端手敲 /as-overseer 或 /as-worker
    W-->>O: 叫醒

    Note over O: 读 WORKFLOW.md 与 context.md<br/>跑长度、悬空指针、sessions.md 检查
    O->>S: 扫 base..HEAD 和工作树
    S-->>O: rc：0 未命中 / 1 命中 / 2 没跑成
    Note over O: 向用户复述最新交接，预检 rc 无条件带上
    O->>G: 核对 sha 是真实提交，且是 HEAD 的祖先
    alt 有文件改动却没有有效 sha
        Note over O: 提交缺失、不是提交、不是 HEAD 祖先<br/>或声称已改的文件仍未提交<br/>（退回时的登记与叫醒，按「每次交接都登记」推出）
        O->>C: 写退回决策：先提交，本轮不放行
        Note over O: 登记 sessions.md
        O-->>W: 叫醒
    else sha 有效，或写明「提交：无」且确认无改动
        Note over O: 核对关键决策点与闸门结果<br/>没有工具判定的质量项，自己读产出<br/>不凭工作者自报放行
        opt rc=1，或 rc=2 修不好，或「安全相关」非空，或项目首轮
            O->>K: 对点名文件做结构化审查（只读）
            K-->>O: 审查报告
        end
        alt 审查通过，闸门无回归
            O->>C: 覆盖「当前状态」轮换部分，追加决策，写「放行到 sha」
            Note over O: 登记 sessions.md
            O-->>W: 叫醒
        else 有回归，或审查要求修改
            O->>C: 写决策与修改要求，不写「放行到」
            Note over O: 登记 sessions.md
            O-->>W: 叫醒
        end
    end
```

### 图 2 读图要点

- **顺序不能换：先提交、再写文件、最后叫醒。** 交接块要写本轮提交的 sha；叫醒消息不带决策内容，只指路。
- **扫描在核对 sha 之前就跑，每轮无条件。** 退回分支也已经拿到了扫描结果。
- **放行是审查通过之后才有的。** 闸门有回归、或审查要求修改时，全局者只写决策和修改要求，不写「放行到」。
- **全局者放行的是一个真实提交。** 「放行到 sha」写进 `context.md`，下一轮扫描的 base 就从这里取，所以工作树里未提交的改动不能放行。
- **图里省略了几处细则**，见 WORKFLOW.md：架构或接口变动时核对强制升级的五类、可重跑闸门何时重跑、critic 在项目目录之外启动时的注册问题。
