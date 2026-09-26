# dual-model-workflow — Windows PowerShell 版
#
# 用法: 在 PowerShell profile（$PROFILE）里 dot-source 本文件:
#   . "C:\path\to\dual-model-workflow\windows\dual-model.ps1"
#
# 前置条件:
#   1. Claude Code CLI 已安装且在 PATH 上（`claude`）。
#   2. 模型切换机制与 Linux 版不同——Linux 版用命令前缀环境变量注入 DeepSeek 端点，
#      Windows 版用 `claude --settings <file>` 只对单个会话叠加配置，需要预先准备:
#        ~\.claude\settings.deepseek.json   — DeepSeek 端点配置（工作者用，内含 API key，绝不提交进仓库）
#      全局者 cc 直接用 ~\.claude\settings.json 的默认配置。
#      注意: 不要改回"整体覆盖 settings.json"的做法——那个文件是所有 Claude Code 进程共享的，
#      一个终端切换会热重载到其它正在运行的会话上，导致两个终端串成同一个模型。
#   3. 模板默认就用本仓库的 templates\（按本脚本位置推算），git pull 即生效，无需复制。
#      要用别处的模板才设 $env:DUAL_MODEL_TEMPLATES。
#
# 命名说明: Windows 上没有 /usr/bin/cc 遮蔽问题，函数名保持 cc / cc-alt / cc-init 与 Linux 版一致。
# （2026-09-15 由 cc-ds 改名 cc-alt——函数本身不认哪个供应商，硬编码在名字里会误导；
#   两端同步改的，见 project-channel channels/cc-alt-rename/。）

# 模板源：环境变量优先；默认指向本仓库的 templates\，按脚本自身位置推算，不写死机器路径。
# 不再回退到 ~\.dual-model\templates —— 那是一份独立拷贝，git pull 不会更新它，
# 于是每个新建项目都静默拿到旧版模板（本机那份停在 2026-07-12，缺全部触发器）。
# VPS 侧同款缺口（cc-init 指向 ~/.claude/scripts/workflow-templates）已于 2026-09-06 修掉。
$script:DUAL_MODEL_TEMPLATES = if ($env:DUAL_MODEL_TEMPLATES) {
  $env:DUAL_MODEL_TEMPLATES
} else {
  Join-Path (Split-Path $PSScriptRoot -Parent) 'templates'
}

# 会话名由项目目录推导，不用固定字符串。否则两个项目同时跑工作流时，
# 两边的会话都叫 "worker"，交接消息可能投进错的项目——比没有自动化更糟。
function _cc_session_slug {
  $s = (Get-Item -LiteralPath $PWD.Path).Name -replace '[^A-Za-z0-9._-]', '-'
  $s = ($s -replace '-{2,}', '-').Trim('-')
  if ($s -match '[A-Za-z0-9]') { return $s }
  # 非 ASCII 目录名会塌成一串横线，两个这样的项目就会撞名——退回整条路径的哈希。
  # Windows 没有 cksum，用 SHA256 取前 8 位十六进制：同路径永远同结果，跨会话稳定。
  # 先转小写再哈希：Windows 路径大小写不敏感，两个终端拿到的 $PWD 大小写可能不同，
  # 不归一化就会算出两个哈希，前缀对不上导致投递失败。
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($PWD.Path.ToLowerInvariant())
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { $hash = $sha.ComputeHash($bytes) } finally { $sha.Dispose() }
  return "proj-" + (($hash[0..3] | ForEach-Object { $_.ToString('x2') }) -join '')
}

# 光有项目段的话每次启动都重名，/resume 列表里堆出一排分不出的条目。
# 每轮一个话题段解决这个问题。只删明确有害的字符，不做白名单——
# PowerShell 字符串是 UTF-16，下面的字符类只匹配 ASCII，不会伤到中文话题。
function _cc_topic_slug {
  param([string]$Topic)
  $t = $Topic -replace '[\x00-\x1F]', ''
  $t = $t -replace '\s+', '-'
  $t = $t -replace '["`$\\/'']', ''
  $t = $t -replace '-{2,}', '-'
  return $t.Trim('-')
}

# 工作模式（WORKFLOW.md「工作模式与旋钮表」）。唯一来源是 context.md 里行首的一行
# `workflow-mode: project|competition|research`，全文件只许一行。0 行 = 还没选（警告，
# 不套用任何模式专属参数）；值不认识或有多行 = 拒绝启动。绝不静默回落默认值——
# 比赛悄悄跑在项目默认值上，正是这里要防的失效。先去掉 \r（文件可能是 CRLF）。
# 与 linux/dual-model.sh 的 _cc_read_mode 同一规格，改一处必须改另一处。
function _cc_read_mode {
  $script:CC_MODE = ""
  if (-not (Test-Path "context.md")) { return $true }
  $lines = @(Get-Content -Encoding UTF8 "context.md" | ForEach-Object { $_ -replace "`r", "" } | Where-Object { $_ -cmatch '^workflow-mode:' })
  if ($lines.Count -eq 0) {
    # 近似写法（缩进、workflow_mode、全角冒号、大小写不同）不能当成「没有这一行」放过去。
    $near = @(Select-String -Path "context.md" -Encoding UTF8 -Pattern '^\s*workflow[-_ ]?mode\s*(:|：)')
    if ($near.Count -gt 0) {
      Write-Host "  context.md 里有像模式行、但不是行首顶格「workflow-mode: <值>」的行：" -ForegroundColor Red
      $near | ForEach-Object { Write-Host "    第 $($_.LineNumber) 行：$($_.Line)" -ForegroundColor Red }
      Write-Host "  改正或删掉它。不启动。" -ForegroundColor Red
      return $false
    }
    return $true
  }
  if ($lines.Count -gt 1) {
    Write-Host "  context.md 里有 $($lines.Count) 行 workflow-mode:，只许一行。不启动。" -ForegroundColor Red
    return $false
  }
  $val = ($lines[0] -replace '^workflow-mode:\s*', '').TrimEnd()
  if (@('project', 'competition', 'research') -ccontains $val) {
    $script:CC_MODE = $val
    return $true
  }
  Write-Host "  context.md: workflow-mode 是「$val」；合法值：project | competition | research。不启动。" -ForegroundColor Red
  return $false
}

# 比赛模式下全局者的 effort（与 scripts/dual-model-mode.sh 的 effort 子命令同一规格）：
# 照传 --effort，默认 high，DUAL_MODEL_EFFORT 可调高。只警告、不拦启动（用户 2026-09-26 裁定）：
# 值不合法、或 CLAUDE_CODE_EFFORT_LEVEL（优先于 --effort）更低时，打印警告后照常启动。
# 不读 settings.json：写在用户 settings 文件里的顶层 effortLevel，2026-09-26 在 Opus 5.5 上实测没生效（机制未查）；
# 用 /effort 保存后写入的按模型 modelSettings 生效。
# 管不到：用户自己在 @args 里传 --effort low。
function _cc_effort_rank([string]$e) {
  switch -CaseSensitive ($e) { 'low' { 1 } 'medium' { 2 } 'high' { 3 } 'xhigh' { 4 } 'max' { 5 } default { 0 } }
}
function _cc_competition_effort {
  $want = 'high'
  if ($env:DUAL_MODEL_EFFORT) {
    if ((_cc_effort_rank $env:DUAL_MODEL_EFFORT) -ge 3) { $want = $env:DUAL_MODEL_EFFORT }
    else { Write-Host "  警告：DUAL_MODEL_EFFORT=「$($env:DUAL_MODEL_EFFORT)」不是 high | xhigh | max（小写）；改用 high。" -ForegroundColor Red }
  }
  $lvl = $env:CLAUDE_CODE_EFFORT_LEVEL
  if ($lvl) {
    if ((_cc_effort_rank $lvl) -eq 0) {
      Write-Host "  警告：CLAUDE_CODE_EFFORT_LEVEL=「$lvl」不是 low | medium | high | xhigh | max；它可能盖过 --effort $want。" -ForegroundColor Red
    } elseif ((_cc_effort_rank $lvl) -lt (_cc_effort_rank $want)) {
      Write-Host "  警告：CLAUDE_CODE_EFFORT_LEVEL=「$lvl」优先于 --effort；本会话会跑在「$lvl」，低于比赛默认「$want」。" -ForegroundColor Red
    }
  }
  $script:CC_EFFORT = $want
}

function _cc_workflow_prompt {
  $script:CC_ROLE_PROMPT = ""
  $script:CC_SESSION_NAME = ""
  $script:CC_MODE = ""
  $script:CC_ROLE = ""
  if (-not (Test-Path "WORKFLOW.md")) { return $true }
  # 机器标识：跨机器时 claude.ai / 手机的会话列表是两台机器混排的，而同一个
  # git 仓库在两端目录名相同 → slug 相同 → 三段式名字逐字撞车。前缀（不是后缀）
  # 才能让搭档前缀匹配继续工作。文件不存在就不加前缀，别的机器不受影响。
  $tag = (Get-Content -Raw "$env:USERPROFILE\.claude\machine-tag" -ErrorAction SilentlyContinue) -replace '[^A-Za-z0-9]', ''
  if ($tag) { $tag = "$tag-" }
  $slug = _cc_session_slug
  Write-Host ""
  Write-Host "  检测到双模型工作流项目" -ForegroundColor Cyan
  Write-Host "  1) 全局者    2) 工作者" -ForegroundColor Cyan
  $role = Read-Host "  当前角色 [1/2]"
  $peer = ""
  switch ($role) {
    "1" { $script:CC_SESSION_NAME = "$tag$slug-overseer"; $peer = "$tag$slug-worker-" }
    "2" { $script:CC_SESSION_NAME = "$tag$slug-worker";   $peer = "$tag$slug-overseer-" }
    default {
      Write-Host ""
      Write-Host "  未选择角色——不注入提示，也不设置会话名。" -ForegroundColor DarkGray
      Write-Host "  （模型按 WORKFLOW.md 默认走工作者；交接保持人工中转）" -ForegroundColor DarkGray
      Write-Host ""
      $script:CC_SESSION_NAME = ""
      return $true
    }
  }
  $script:CC_ROLE = $role
  if (-not (_cc_read_mode)) { return $false }

  $topic = _cc_topic_slug (Read-Host "  本轮话题（可选，回车跳过）")
  # 话题为空也得有个区分段，否则 /resume 的条目又重名了。
  if (-not $topic) { $topic = Get-Date -Format 'MMdd-HHmm' }
  $script:CC_SESSION_NAME = "$($script:CC_SESSION_NAME)-$topic"

  $findPeer = "对方的会话名以「$peer」开头，但后缀是对方在它自己的终端启动时填的，你算不出来：每次发送前都要跑一次 ListAgents，找名字以该前缀开头的那一行。恰好一条匹配才发送，按行里印的完整名字用 SendMessage 发（格式见 WORKFLOW.md 的「会话间直接通知」一节）。零条或多条匹配，一律回退到该节写的人工中转，不要猜。每一次发送前都要重查，不要沿用上一轮查到的名字，也不要用用户贴给你的列表——对方终端一旦重开名字就变了，以 ListAgents 的实时输出为准。"
  switch ($role) {
    "1" {
      $script:CC_ROLE_PROMPT = "你当前是全局者。你的会话名是「$($script:CC_SESSION_NAME)」。$findPeer 读 context.md 了解现状，制定或确认方向后写入 context.md。"
    }
    "2" {
      $script:CC_ROLE_PROMPT = "你当前是工作者。你的会话名是「$($script:CC_SESSION_NAME)」。$findPeer 读 WORKFLOW.md 和 context.md 获取当前任务，按方向执行。"
    }
  }
  if ($script:CC_MODE) {
    $script:CC_ROLE_PROMPT += " 工作模式：$($script:CC_MODE)（各旋钮默认值见 WORKFLOW.md「工作模式与旋钮表」）。"
  } elseif ($role -eq "1") {
    $script:CC_ROLE_PROMPT += " 本项目还没有选工作模式：本轮第一件事是向用户提出模式建议和该模式的默认参数（见 WORKFLOW.md「工作模式与旋钮表」）。"
  }

  $color = if ($role -eq "1") { "Yellow" } else { "Green" }
  Write-Host ""
  Write-Host "  - 角色已静默注入系统提示（不占用你的第一条消息）。" -ForegroundColor $color
  Write-Host "  - 会话名：$($script:CC_SESSION_NAME)" -ForegroundColor $color
  Write-Host "  - 对方前缀：$peer*   （发送时用 ListAgents 现查）" -ForegroundColor $color
  if ($script:CC_MODE) {
    Write-Host "  - 工作模式：$($script:CC_MODE)" -ForegroundColor $color
  } else {
    Write-Host "  - 工作模式：未选（context.md 里没有 workflow-mode: 行）" -ForegroundColor Red
    Write-Host "    比赛项目写入模式后要重启全局者，比赛模式的 effort 默认值才会生效。" -ForegroundColor Red
  }
  if ($role -eq "1") {
    Write-Host "  工作者跑起来之后，交接会自动发给它。" -ForegroundColor $color
    Write-Host "  人工兜底：在工作者终端输入 /as-worker" -ForegroundColor $color
  } else {
    Write-Host "  全局者跑起来之后，交接会自动发给它。" -ForegroundColor $color
    Write-Host "  人工兜底：在全局者终端输入 /as-overseer" -ForegroundColor $color
  }
  Write-Host ""
  return $true
}

# 把会话名和角色提示拼成参数数组。PowerShell 没有 bash 的 ${VAR:+--name} 条件展开，
# 而拼字符串再 Invoke-Expression 会让含空格和引号的提示词被二次解析——用数组传。
function _cc_launch_args {
  $a = @()
  if ($script:CC_SESSION_NAME) { $a += '--name'; $a += $script:CC_SESSION_NAME }
  if ($script:CC_ROLE_PROMPT)  { $a += '--append-system-prompt'; $a += $script:CC_ROLE_PROMPT }
  if ($script:CC_EFFORT)       { $a += '--effort'; $a += $script:CC_EFFORT }
  return ,$a
}

# 把角色放进环境变量 DUAL_MODEL_ROLE 给钩子用（K10 强制回应的 Stop 钩子只拦全局者），启动完恢复原值。
# 注意：脚本块里的 $args 是脚本块自己的参数，所以调用方要把自己的 $args 作为 $rest 显式传进来。
function _cc_with_role_env([scriptblock]$run, [object[]]$rest) {
  $old = $env:DUAL_MODEL_ROLE
  $env:DUAL_MODEL_ROLE = switch ($script:CC_ROLE) { '1' { 'overseer' } '2' { 'worker' } default { '' } }
  try { & $run @rest } finally { $env:DUAL_MODEL_ROLE = $old }
}

# 全局者 — Claude（用 ~\.claude\settings.json 里的默认配置，不做任何切换）
function cc {
  $script:CC_EFFORT = ""
  if (-not (_cc_workflow_prompt)) { return }
  if ($script:CC_MODE -eq 'competition' -and $script:CC_ROLE -eq '1') {
    _cc_competition_effort
    Write-Host "  - Effort：--effort $($script:CC_EFFORT)（比赛模式默认）" -ForegroundColor Yellow
  }
  $cliArgs = _cc_launch_args
  _cc_with_role_env { claude @cliArgs @args } $args
}

# 工作者 — 第二模型（用 --settings 只对本会话叠加端点配置；例子用 DeepSeek，换成
# 任何 Anthropic 兼容端点都一样，改 settings.<name>.json 的内容即可，函数不认供应商）
function cc-alt {
  $altSettings = "$env:USERPROFILE\.claude\settings.deepseek.json"
  if (-not (Test-Path $altSettings)) {
    Write-Error "cc-alt: 未找到 ~\.claude\settings.deepseek.json，请先准备第二模型端点配置。"
    return
  }
  # 文件存在不代表里面有密钥。CC 找不到 ANTHROPIC_AUTH_TOKEN/ANTHROPIC_API_KEY 时
  # 不会报错，而是把当前登录的 Claude 凭据发给 env.ANTHROPIC_BASE_URL 指向的端点——
  # 对一个第二模型端点来说，这就是把你的 Claude 账号凭据发给了别处。文件存在但
  # 密钥字段缺失/空这种半配置状态必须在这里挡住，不能指望 claude 自己拒绝。
  try {
    $altConfig = Get-Content -Raw $altSettings | ConvertFrom-Json
  } catch {
    Write-Error "cc-alt: $altSettings 不是合法 JSON。"
    return
  }
  if ([string]::IsNullOrEmpty($altConfig.env.ANTHROPIC_AUTH_TOKEN) -and [string]::IsNullOrEmpty($altConfig.env.ANTHROPIC_API_KEY)) {
    Write-Error "cc-alt: $altSettings 里 env.ANTHROPIC_AUTH_TOKEN / env.ANTHROPIC_API_KEY 都是空的——不启动，以免把 Claude 凭据发给 env.ANTHROPIC_BASE_URL 指向的端点。"
    return
  }
  $script:CC_EFFORT = ""
  if (-not (_cc_workflow_prompt)) { return }
  $cliArgs = _cc_launch_args
  _cc_with_role_env { claude --settings $altSettings @cliArgs @args } $args
}

# 在当前项目目录初始化双模型工作流
function cc-init {
  if (Test-Path "WORKFLOW.md") {
    Write-Host "  WORKFLOW.md 已存在，跳过。" -ForegroundColor Yellow
    return
  }
  $tpl = $script:DUAL_MODEL_TEMPLATES
  if (-not (Test-Path "$tpl\WORKFLOW.md")) {
    Write-Error "  模板未找到: $tpl`n  把仓库的 templates\ 复制过去，或设置 `$env:DUAL_MODEL_TEMPLATES。"
    return
  }
  Copy-Item "$tpl\WORKFLOW.md" .\
  Copy-Item "$tpl\CLAUDE.md" .\
  Copy-Item "$tpl\context.md" .\
  Copy-Item "$tpl\context_history.md" .\
  if (Test-Path "$tpl\.claude") {
    New-Item -ItemType Directory -Force .claude\commands, .claude\agents | Out-Null
    Get-ChildItem "$tpl\.claude\commands\*.md" -ErrorAction SilentlyContinue | ForEach-Object {
      if (-not (Test-Path ".claude\commands\$($_.Name)")) { Copy-Item $_.FullName .claude\commands\ }
    }
    Get-ChildItem "$tpl\.claude\agents\*.md" -ErrorAction SilentlyContinue | ForEach-Object {
      if (-not (Test-Path ".claude\agents\$($_.Name)")) { Copy-Item $_.FullName .claude\agents\ }
    }
    # K10 钩子（Stop = 强制回应，SubagentStop = 报告落盘）。已有 settings.json 就不覆盖，提示手动合并。
    # 注意：钩子命令写的是 python3 "$HOME/..."，在 Windows 上未实测（python 可执行名、$HOME 展开都要在 MSI 上确认）。
    if (-not (Test-Path "$env:USERPROFILE\.claude\scripts\k10-stop-gate.py")) {
      Write-Host "  注意：~\.claude\scripts\ 下没有 K10 钩子脚本；钩子只会提示「未安装」。先按 README 安装 scripts\。" -ForegroundColor Yellow
    }
    if (Test-Path ".claude\settings.json") {
      Write-Host "  注意：.claude\settings.json 已存在，请手动合并 $tpl\.claude\settings.json 里的 K10 钩子。" -ForegroundColor Yellow
    } elseif (Test-Path "$tpl\.claude\settings.json") {
      Copy-Item "$tpl\.claude\settings.json" .claude\settings.json
    }
  }
  if (Test-Path "$tpl\.workflow") {
    New-Item -ItemType Directory -Force .workflow | Out-Null
    Get-ChildItem -Recurse -File "$tpl\.workflow" | ForEach-Object {
      $rel = $_.FullName.Substring((Resolve-Path "$tpl\.workflow").Path.Length).TrimStart('\')
      $dst = Join-Path .workflow $rel
      if (-not (Test-Path $dst)) {
        New-Item -ItemType Directory -Force (Split-Path $dst) | Out-Null
        Copy-Item $_.FullName $dst
      }
    }
  }
  Write-Host "  双模型工作流已初始化：" -ForegroundColor Cyan
  Write-Host "  WORKFLOW.md          — 角色定义和切换规则"
  Write-Host "  CLAUDE.md            — 告知模型启动时读取工作流"
  Write-Host "  context.md           — 模型间共享上下文"
  Write-Host "  context_history.md   — 归档落点（空表头，phase 关闭时追加）"
  Write-Host "  .workflow\           — K10 第三者召唤模板 + k10.example.json（见 WORKFLOW.md「K10 第三者」）"
  if (Test-Path ".claude\commands") {
    Write-Host "  .claude\commands\    — 角色切换 slash 命令（/as-overseer、/as-worker）"
  }
  if (Test-Path ".claude\agents") {
    Write-Host "  .claude\agents\      — critic 子代理（安全相关审查，用 Haiku 跑）"
  }
}
