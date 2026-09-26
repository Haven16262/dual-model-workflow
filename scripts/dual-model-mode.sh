#!/usr/bin/env bash
# dual-model-mode.sh — the ONE implementation of the workflow-mode rules
# (WORKFLOW.md, section 工作模式与旋钮表). Every bash launcher (the reference
# linux/dual-model.sh, ~/.bashrc's cc/cc-alt, mgr-open.sh) calls this instead of
# carrying its own copy; windows/dual-model.ps1 is a port of the same spec.
# Install: cp scripts/dual-model-mode.sh ~/.claude/scripts/
#
#   dual-model-mode.sh mode [context.md]
#     stdout: the mode (project|competition|research), or nothing if no mode line.
#     exit 0 = usable (mode or none); exit 1 = refuse to launch (reason on stderr):
#       an unknown value, more than one line, or a near-miss line (indented,
#       workflow_mode, full-width colon, other case) with no exact line.
#     Never falls back to a default silently. CR is stripped (CRLF files).
#
#   dual-model-mode.sh model
#     stdout: the model to pass with --model for a competition-mode Overseer.
#     Default opus; DUAL_MODEL_MODEL may override (any value `claude --model` accepts).
#     Needed because the user-level default (settings.json "model") is sonnet to save
#     quota (user decision 2026-09-26): Opus must be requested explicitly.
#
#   dual-model-mode.sh effort
#     stdout: the effort to pass with --effort for a competition-mode Overseer.
#     Default high; DUAL_MODEL_EFFORT may raise it. Warn-only (user decision
#     2026-09-26): bad values and a lower CLAUDE_CODE_EFFORT_LEVEL (which outranks
#     --effort) print a warning on stderr but never block the launch. Exit 0.
#     Not covered: an explicit `--effort low` the user passes on the command line.
set -u

rank() { case "$1" in low) echo 1 ;; medium) echo 2 ;; high) echo 3 ;; xhigh) echo 4 ;; max) echo 5 ;; *) echo 0 ;; esac; }

cmd_mode() {
  local ctx="${1:-context.md}" lines n near val
  [ -f "$ctx" ] || return 0
  lines=$(tr -d '\r' < "$ctx" | grep -E '^workflow-mode:')
  n=$(printf '%s' "$lines" | grep -c '^')
  if [ "$n" -eq 0 ]; then
    near=$(tr -d '\r' < "$ctx" | grep -niE '^[[:space:]]*workflow[-_ ]?mode[[:space:]]*(:|：)')
    if [ -n "$near" ]; then
      echo "  $ctx has a line that looks like a mode line but is not exactly 'workflow-mode: <value>' at line start:" >&2
      printf '%s\n' "$near" | sed 's/^/    line /' >&2
      echo "  Fix it (or remove it). Not launching." >&2
      return 1
    fi
    return 0
  fi
  if [ "$n" -gt 1 ]; then
    echo "  $ctx has $n 'workflow-mode:' lines; exactly one is allowed. Not launching." >&2
    return 1
  fi
  val=$(printf '%s' "$lines" | sed -E 's/^workflow-mode:[[:space:]]*//; s/[[:space:]]+$//')
  case "$val" in
    project|competition|research) printf '%s\n' "$val"; return 0 ;;
  esac
  echo "  $ctx: workflow-mode is '$val'; allowed: project | competition | research. Not launching." >&2
  return 1
}

cmd_effort() {
  local want="high" env_level="${CLAUDE_CODE_EFFORT_LEVEL:-}"
  if [ -n "${DUAL_MODEL_EFFORT:-}" ]; then
    if [ "$(rank "$DUAL_MODEL_EFFORT")" -ge 3 ]; then
      want="$DUAL_MODEL_EFFORT"
    else
      echo "  WARNING: DUAL_MODEL_EFFORT='$DUAL_MODEL_EFFORT' is not high | xhigh | max (lowercase); using high." >&2
    fi
  fi
  if [ -n "$env_level" ]; then
    if [ "$(rank "$env_level")" -eq 0 ]; then
      echo "  WARNING: CLAUDE_CODE_EFFORT_LEVEL='$env_level' is not low | medium | high | xhigh | max; it may override --effort $want." >&2
    elif [ "$(rank "$env_level")" -lt "$(rank "$want")" ]; then
      echo "  WARNING: CLAUDE_CODE_EFFORT_LEVEL='$env_level' outranks --effort; this session will run at '$env_level', below the competition default '$want'." >&2
    fi
  fi
  printf '%s\n' "$want"
}

cmd_model() { printf '%s\n' "${DUAL_MODEL_MODEL:-opus}"; }

case "${1:-}" in
  mode) shift; cmd_mode "$@" ;;
  model) cmd_model ;;
  effort) cmd_effort ;;
  *) echo "usage: dual-model-mode.sh mode [context.md] | model | effort" >&2; exit 2 ;;
esac
