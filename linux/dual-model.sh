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

_cc_workflow_prompt() {
  _CC_ROLE_PROMPT=""
  [ ! -f "WORKFLOW.md" ] && return
  echo ""
  echo "  Dual-model workflow project detected"
  echo "  1) Overseer    2) Worker"
  printf "  Current role [1/2]: "
  read _role
  case $_role in
    1)
      _CC_ROLE_PROMPT="You are the Overseer. Read context.md for current state, set or confirm direction, write it to context.md. When done, say: 'Decision written, you can switch back to the Worker.'"
      echo ""
      echo "  - Role injected silently into the system prompt (doesn't consume your first message)."
      echo "  To switch: in the Worker terminal, type:"
      echo "  'The Overseer changed something, check the context file.'"
      echo "  (or use the /as-worker slash command)"
      ;;
    2)
      _CC_ROLE_PROMPT="You are the Worker. Read WORKFLOW.md and context.md for the current task and execute. On a trigger condition, stop and say: '[reason], please switch to the Overseer.'"
      echo ""
      echo "  - Role injected silently into the system prompt (doesn't consume your first message)."
      echo "  To switch: in the Overseer terminal, type:"
      echo "  'The Worker changed something, check the context file.'"
      echo "  (or use the /as-overseer slash command)"
      ;;
    *)
      echo ""
      echo "  No role selected — no prompt injected (model defaults to Worker per WORKFLOW.md)."
      ;;
  esac
  echo ""
}

# Overseer — Claude (or whatever your default `claude` provider is)
cc() {
  _cc_workflow_prompt
  claude ${_CC_ROLE_PROMPT:+--append-system-prompt} ${_CC_ROLE_PROMPT:+"$_CC_ROLE_PROMPT"} "$@"
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
  claude ${_CC_ROLE_PROMPT:+--append-system-prompt} ${_CC_ROLE_PROMPT:+"$_CC_ROLE_PROMPT"} "$@"
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
