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
#   3. 模板放在 $env:DUAL_MODEL_TEMPLATES（默认 ~\.dual-model\templates）——
#      把本仓库的 templates\ 整个复制过去（含 .claude\ 隐藏目录）。
#
# 命名说明: Windows 上没有 /usr/bin/cc 遮蔽问题，函数名保持 cc / cc-ds / cc-init 与 Linux 版一致。

$script:DUAL_MODEL_TEMPLATES = if ($env:DUAL_MODEL_TEMPLATES) { $env:DUAL_MODEL_TEMPLATES } else { "$env:USERPROFILE\.dual-model\templates" }

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

function _cc_workflow_prompt {
  $script:CC_ROLE_PROMPT = ""
  $script:CC_SESSION_NAME = ""
  if (-not (Test-Path "WORKFLOW.md")) { return }
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
      return
    }
  }

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

  $color = if ($role -eq "1") { "Yellow" } else { "Green" }
  Write-Host ""
  Write-Host "  - 角色已静默注入系统提示（不占用你的第一条消息）。" -ForegroundColor $color
  Write-Host "  - 会话名：$($script:CC_SESSION_NAME)" -ForegroundColor $color
  Write-Host "  - 对方前缀：$peer*   （发送时用 ListAgents 现查）" -ForegroundColor $color
  if ($role -eq "1") {
    Write-Host "  工作者跑起来之后，交接会自动发给它。" -ForegroundColor $color
    Write-Host "  人工兜底：在工作者终端输入 /as-worker" -ForegroundColor $color
  } else {
    Write-Host "  全局者跑起来之后，交接会自动发给它。" -ForegroundColor $color
    Write-Host "  人工兜底：在全局者终端输入 /as-overseer" -ForegroundColor $color
  }
  Write-Host ""
}

# 把会话名和角色提示拼成参数数组。PowerShell 没有 bash 的 ${VAR:+--name} 条件展开，
# 而拼字符串再 Invoke-Expression 会让含空格和引号的提示词被二次解析——用数组传。
function _cc_launch_args {
  $a = @()
  if ($script:CC_SESSION_NAME) { $a += '--name'; $a += $script:CC_SESSION_NAME }
  if ($script:CC_ROLE_PROMPT)  { $a += '--append-system-prompt'; $a += $script:CC_ROLE_PROMPT }
  return ,$a
}

# 全局者 — Claude（用 ~\.claude\settings.json 里的默认配置，不做任何切换）
function cc {
  _cc_workflow_prompt
  $cliArgs = _cc_launch_args
  claude @cliArgs @args
}

# 工作者 — DeepSeek（用 --settings 只对本会话叠加 DeepSeek 端点配置）
function cc-ds {
  $dsSettings = "$env:USERPROFILE\.claude\settings.deepseek.json"
  if (-not (Test-Path $dsSettings)) {
    Write-Error "cc-ds: 未找到 ~\.claude\settings.deepseek.json，请先准备 DeepSeek 端点配置。"
    return
  }
  _cc_workflow_prompt
  $cliArgs = _cc_launch_args
  claude --settings $dsSettings @cliArgs @args
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
  if (Test-Path "$tpl\.claude") {
    New-Item -ItemType Directory -Force .claude\commands, .claude\agents | Out-Null
    Get-ChildItem "$tpl\.claude\commands\*.md" -ErrorAction SilentlyContinue | ForEach-Object {
      if (-not (Test-Path ".claude\commands\$($_.Name)")) { Copy-Item $_.FullName .claude\commands\ }
    }
    Get-ChildItem "$tpl\.claude\agents\*.md" -ErrorAction SilentlyContinue | ForEach-Object {
      if (-not (Test-Path ".claude\agents\$($_.Name)")) { Copy-Item $_.FullName .claude\agents\ }
    }
  }
  Write-Host "  双模型工作流已初始化：" -ForegroundColor Cyan
  Write-Host "  WORKFLOW.md          — 角色定义和切换规则"
  Write-Host "  CLAUDE.md            — 告知模型启动时读取工作流"
  Write-Host "  context.md           — 模型间共享上下文"
  if (Test-Path ".claude\commands") {
    Write-Host "  .claude\commands\    — 角色切换 slash 命令（/as-overseer、/as-worker）"
  }
  if (Test-Path ".claude\agents") {
    Write-Host "  .claude\agents\      — critic 子代理（安全相关审查，用 Haiku 跑）"
  }
}
