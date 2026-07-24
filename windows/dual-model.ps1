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

function _cc_workflow_prompt {
  $script:CC_ROLE_PROMPT = ""
  if (-not (Test-Path "WORKFLOW.md")) { return }
  Write-Host ""
  Write-Host "  检测到双模型工作流项目" -ForegroundColor Cyan
  Write-Host "  1) 全局者    2) 工作者" -ForegroundColor Cyan
  $role = Read-Host "  当前角色 [1/2]"
  switch ($role) {
    "1" {
      $script:CC_ROLE_PROMPT = "你当前是全局者。读 context.md 了解现状，制定或确认方向后写入 context.md。完成后说：「决策已写入，可切换回工作者继续。」"
      Write-Host ""
      Write-Host "  - 角色已静默注入系统提示（不占用你的第一条消息）。" -ForegroundColor Yellow
      Write-Host "  切换方式：在工作者终端输入「全局者修改了内容，查看 context 文件」" -ForegroundColor Yellow
      Write-Host "  （或使用 /as-worker 命令）" -ForegroundColor Yellow
    }
    "2" {
      $script:CC_ROLE_PROMPT = "你当前是工作者。读 WORKFLOW.md 和 context.md 获取当前任务，按方向执行。遇到触发条件时停下说：「[原因]，请切换到全局者。」"
      Write-Host ""
      Write-Host "  - 角色已静默注入系统提示（不占用你的第一条消息）。" -ForegroundColor Green
      Write-Host "  切换方式：在全局者终端输入「工作者修改了内容，查看 context 文件」" -ForegroundColor Green
      Write-Host "  （或使用 /as-overseer 命令）" -ForegroundColor Green
    }
    default {
      Write-Host ""
      Write-Host "  未选择角色——不注入提示（模型按 WORKFLOW.md 默认走工作者）。" -ForegroundColor DarkGray
    }
  }
  Write-Host ""
}

# 全局者 — Claude（用 ~\.claude\settings.json 里的默认配置，不做任何切换）
function cc {
  _cc_workflow_prompt
  if ($script:CC_ROLE_PROMPT) { claude --append-system-prompt $script:CC_ROLE_PROMPT @args } else { claude @args }
}

# 工作者 — DeepSeek（用 --settings 只对本会话叠加 DeepSeek 端点配置）
function cc-ds {
  $dsSettings = "$env:USERPROFILE\.claude\settings.deepseek.json"
  if (-not (Test-Path $dsSettings)) {
    Write-Error "cc-ds: 未找到 ~\.claude\settings.deepseek.json，请先准备 DeepSeek 端点配置。"
    return
  }
  _cc_workflow_prompt
  if ($script:CC_ROLE_PROMPT) { claude --settings $dsSettings --append-system-prompt $script:CC_ROLE_PROMPT @args } else { claude --settings $dsSettings @args }
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
