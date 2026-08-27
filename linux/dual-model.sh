# dual-model-workflow — shell helpers
#
# Source this from your ~/.bashrc (or ~/.zshrc):
#   source /path/to/dual-model-workflow/linux/dual-model.sh
#
# Prerequisites:
#   1. Claude Code CLI installed and on PATH (`claude`).
#   2. A DeepSeek API key exported in your shell profile BEFORE this file is sourced:
#        export DEEPSEEK_API_KEY="sk-your-deepseek-key"
#      (Never commit your real key. Keep it out of version control.)
#   3. Templates available at $DUAL_MODEL_TEMPLATES
#      (defaults to ~/.dual-model/templates — copy this repo's templates/ there,
#       or set DUAL_MODEL_TEMPLATES to wherever you keep them).
#
# NOTE ON NAMING: the functions below are named `cc`, `cc-ds`, `cc-init`
# to match the reference write-up. `cc` will shadow the system C compiler
# (/usr/bin/cc) in interactive shells. If you do C development, rename these
# (e.g. `dm`, `dm-ds`, `dm-init`) — they are plain functions, just change the names.

: "${DUAL_MODEL_TEMPLATES:=$HOME/.dual-model/templates}"

# Session names are derived from the project directory, not fixed strings.
# Two projects running the workflow at the same time would otherwise both have
# a session called "worker", and a handoff message could land in the wrong
# project — worse than having no automation at all.
_cc_session_slug() {
  local _s
  _s=$(printf '%s' "$(basename "$PWD")" | tr -c 'A-Za-z0-9._-' '-' | tr -s '-' \
       | sed 's/^-*//; s/-*$//')
  # A non-ASCII directory name collapses to nothing but dashes, and two such
  # projects would then share a slug — fall back to a hash of the full path.
  case "$_s" in
    *[A-Za-z0-9]*) printf '%s' "$_s" ;;
    *)             printf 'proj-%s' "$(printf '%s' "$PWD" | cksum | cut -d' ' -f1)" ;;
  esac
}

# The project slug alone repeats on every launch, so the /resume picker fills up
# with rows that are impossible to tell apart. A per-launch topic fixes that.
# Only clearly harmful characters are stripped, never a whitelist: tr works on
# bytes, and every byte of a multi-byte character is >= 0x80, so ASCII deletions
# can't corrupt a CJK topic.
_cc_topic_slug() {
  printf '%s' "$1" \
    | tr -d '\000-\037' \
    | tr -s '[:space:]' '-' \
    | tr -d '"`$\\/' \
    | tr -d "'" \
    | tr -s '-' \
    | sed 's/^-*//; s/-*$//'
}

_cc_workflow_prompt() {
  _CC_ROLE_PROMPT=""
  _CC_SESSION_NAME=""
  [ ! -f "WORKFLOW.md" ] && return
  local _slug _role _topic _peer _tag
  # 机器标识：跨机器时 claude.ai / 手机的会话列表是两台机器混排的，而同一个
  # git 仓库在两端目录名相同 → slug 相同 → 三段式名字逐字撞车。前缀（不是后缀）
  # 才能让搭档前缀匹配继续工作。文件不存在就不加前缀，别的机器不受影响。
  _tag=$(tr -cd 'A-Za-z0-9' < ~/.claude/machine-tag 2>/dev/null)
  [ -n "$_tag" ] && _tag="${_tag}-"
  _slug=$(_cc_session_slug)
  echo ""
  echo "  Dual-model workflow project detected"
  echo "  1) Overseer    2) Worker"
  printf "  Current role [1/2]: "
  read _role
  case $_role in
    1) _CC_SESSION_NAME="${_tag}${_slug}-overseer"; _peer="${_tag}${_slug}-worker-" ;;
    2) _CC_SESSION_NAME="${_tag}${_slug}-worker";   _peer="${_tag}${_slug}-overseer-" ;;
    *)
      echo ""
      echo "  No role selected — no prompt injected, no session name set."
      echo "  (model defaults to Worker per WORKFLOW.md; handoffs stay manual)"
      echo ""
      return
      ;;
  esac

  printf "  Topic for this round (optional, Enter to skip): "
  read _topic
  _topic=$(_cc_topic_slug "$_topic")
  # Empty topic still needs a discriminator, or the /resume rows collide again.
  [ -z "$_topic" ] && _topic=$(date +%m%d-%H%M)
  _CC_SESSION_NAME="${_CC_SESSION_NAME}-${_topic}"

  case $_role in
    1)
      _CC_ROLE_PROMPT="You are the Overseer. Your session name is '${_CC_SESSION_NAME}'. The Worker's session name starts with '${_peer}' but its suffix is picked at the Worker's own launch, so you cannot compute it: run ListAgents before EVERY send and use the row whose name starts with that prefix. Re-check every time: never reuse a name from an earlier lookup or one your user pasted, because a peer's name changes when its terminal is restarted. Exactly one match — send to it with SendMessage as described in the cross-session notification section of WORKFLOW.md. No match or several — fall back to the manual handoff described there, do not guess. Read context.md for current state, set or confirm direction, write it to context.md."
      ;;
    2)
      _CC_ROLE_PROMPT="You are the Worker. Your session name is '${_CC_SESSION_NAME}'. The Overseer's session name starts with '${_peer}' but its suffix is picked at the Overseer's own launch, so you cannot compute it: run ListAgents before EVERY send and use the row whose name starts with that prefix. Re-check every time: never reuse a name from an earlier lookup or one your user pasted, because a peer's name changes when its terminal is restarted. Exactly one match — send to it with SendMessage as described in the cross-session notification section of WORKFLOW.md. No match or several — fall back to the manual handoff described there, do not guess. Read WORKFLOW.md and context.md for the current task and execute."
      ;;
  esac

  echo ""
  echo "  - Role injected silently into the system prompt (doesn't consume your first message)."
  echo "  - Session name: ${_CC_SESSION_NAME}"
  echo "  - Peer prefix:  ${_peer}*   (resolved via ListAgents at send time)"
  if [ "$_role" = 1 ]; then
    echo "  Handoffs are sent to the Worker automatically once it is running."
    echo "  Manual fallback: in the Worker terminal, type /as-worker"
  else
    echo "  Handoffs are sent to the Overseer automatically once it is running."
    echo "  Manual fallback: in the Overseer terminal, type /as-overseer"
  fi
  echo ""
}

# Overseer — Claude (or whatever your default `claude` provider is)
cc() {
  _cc_workflow_prompt
  claude ${_CC_SESSION_NAME:+--name} ${_CC_SESSION_NAME:+"$_CC_SESSION_NAME"} \
         ${_CC_ROLE_PROMPT:+--append-system-prompt} ${_CC_ROLE_PROMPT:+"$_CC_ROLE_PROMPT"} "$@"
}

# Worker — DeepSeek via Claude Code's Anthropic-compatible endpoint
cc-ds() {
  if [ -z "$DEEPSEEK_API_KEY" ]; then
    echo "cc-ds: DEEPSEEK_API_KEY is not set. Export it in your shell profile first." >&2
    return 1
  fi
  _cc_workflow_prompt
  # Worker-only settings overlay. On Linux the DeepSeek endpoint comes from the
  # environment variables below, so this file is OPTIONAL and carries only hooks
  # (the worker permission guard, a vision co-pilot, ...). Windows needs it for
  # the endpoint itself and errors when missing; here a missing file must not
  # stop the Worker from launching, hence the existence check. Without this flag
  # anything you put in settings.deepseek.json is silently never loaded.
  local _ds_settings=~/.claude/settings.deepseek.json
  [ -f "$_ds_settings" ] || _ds_settings=""
  ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic \
  ANTHROPIC_AUTH_TOKEN=$DEEPSEEK_API_KEY \
  ANTHROPIC_MODEL="deepseek-v4-pro[1m]" \
  ANTHROPIC_DEFAULT_OPUS_MODEL="deepseek-v4-pro[1m]" \
  ANTHROPIC_DEFAULT_SONNET_MODEL="deepseek-v4-pro[1m]" \
  ANTHROPIC_DEFAULT_HAIKU_MODEL=deepseek-v4-flash \
  CLAUDE_CODE_SUBAGENT_MODEL=deepseek-v4-flash \
  claude ${_ds_settings:+--settings} ${_ds_settings:+"$_ds_settings"} \
         ${_CC_SESSION_NAME:+--name} ${_CC_SESSION_NAME:+"$_CC_SESSION_NAME"} \
         ${_CC_ROLE_PROMPT:+--append-system-prompt} ${_CC_ROLE_PROMPT:+"$_CC_ROLE_PROMPT"} "$@"
}

# Initialize the dual-model workflow in the current project directory
cc-init() {
  if [ -f "WORKFLOW.md" ]; then
    echo "  WORKFLOW.md already exists, skipping."
    return
  fi
  if [ ! -d "$DUAL_MODEL_TEMPLATES" ]; then
    echo "  Templates not found at: $DUAL_MODEL_TEMPLATES" >&2
    echo "  Copy this repo's templates/ there, or set DUAL_MODEL_TEMPLATES." >&2
    return 1
  fi
  cp "$DUAL_MODEL_TEMPLATES/WORKFLOW.md" ./
  cp "$DUAL_MODEL_TEMPLATES/CLAUDE.md" ./
  cp "$DUAL_MODEL_TEMPLATES/context.md" ./
  if [ -d "$DUAL_MODEL_TEMPLATES/.claude" ]; then
    mkdir -p .claude/commands .claude/agents
    cp -n "$DUAL_MODEL_TEMPLATES/.claude/commands/"*.md .claude/commands/ 2>/dev/null
    cp -n "$DUAL_MODEL_TEMPLATES/.claude/agents/"*.md .claude/agents/ 2>/dev/null
  fi
  echo "  Dual-model workflow initialized:"
  echo "  WORKFLOW.md          — role definitions and switch rules"
  echo "  CLAUDE.md            — tells the model to read the workflow on startup"
  echo "  context.md           — shared context between the two models"
  if [ -d .claude/commands ]; then
    echo "  .claude/commands/    — role-switch slash commands (/as-overseer, /as-worker)"
  fi
  if [ -d .claude/agents ]; then
    echo "  .claude/agents/      — critic subagent (security-relevant review, runs on Haiku)"
  fi
}
