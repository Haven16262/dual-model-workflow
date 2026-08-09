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

_cc_workflow_prompt() {
  _CC_ROLE_PROMPT=""
  _CC_SESSION_NAME=""
  [ ! -f "WORKFLOW.md" ] && return
  local _slug
  _slug=$(_cc_session_slug)
  echo ""
  echo "  Dual-model workflow project detected"
  echo "  1) Overseer    2) Worker"
  printf "  Current role [1/2]: "
  read _role
  case $_role in
    1)
      _CC_SESSION_NAME="${_slug}-overseer"
      _CC_ROLE_PROMPT="You are the Overseer. Session names for this project: yours is '${_slug}-overseer', the Worker's is '${_slug}-worker' — address it with SendMessage as described in the cross-session notification section of WORKFLOW.md. Read context.md for current state, set or confirm direction, write it to context.md."
      echo ""
      echo "  - Role injected silently into the system prompt (doesn't consume your first message)."
      echo "  - Session name: ${_CC_SESSION_NAME}  (peer: ${_slug}-worker)"
      echo "  Handoffs are sent to the Worker automatically once it is running."
      echo "  Manual fallback: in the Worker terminal, type /as-worker"
      ;;
    2)
      _CC_SESSION_NAME="${_slug}-worker"
      _CC_ROLE_PROMPT="You are the Worker. Session names for this project: yours is '${_slug}-worker', the Overseer's is '${_slug}-overseer' — address it with SendMessage as described in the cross-session notification section of WORKFLOW.md. Read WORKFLOW.md and context.md for the current task and execute."
      echo ""
      echo "  - Role injected silently into the system prompt (doesn't consume your first message)."
      echo "  - Session name: ${_CC_SESSION_NAME}  (peer: ${_slug}-overseer)"
      echo "  Handoffs are sent to the Overseer automatically once it is running."
      echo "  Manual fallback: in the Overseer terminal, type /as-overseer"
      ;;
    *)
      echo ""
      echo "  No role selected — no prompt injected, no session name set."
      echo "  (model defaults to Worker per WORKFLOW.md; handoffs stay manual)"
      ;;
  esac
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
  ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic \
  ANTHROPIC_AUTH_TOKEN=$DEEPSEEK_API_KEY \
  ANTHROPIC_MODEL="deepseek-v4-pro[1m]" \
  ANTHROPIC_DEFAULT_OPUS_MODEL="deepseek-v4-pro[1m]" \
  ANTHROPIC_DEFAULT_SONNET_MODEL="deepseek-v4-pro[1m]" \
  ANTHROPIC_DEFAULT_HAIKU_MODEL=deepseek-v4-flash \
  CLAUDE_CODE_SUBAGENT_MODEL=deepseek-v4-flash \
  claude ${_CC_SESSION_NAME:+--name} ${_CC_SESSION_NAME:+"$_CC_SESSION_NAME"} \
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
