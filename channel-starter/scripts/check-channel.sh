#!/usr/bin/env bash
# check-channel.sh — integrity gate for a letter-channel repository.
#
# Run by the READER after every `git pull`, before reading anything new.
# Why the reader and not the author: an author can skip his own gate, but cannot
# skip the fact that the other side is about to read the letter.
#
# Usage:  scripts/check-channel.sh [<repo-root>]     (default: the parent of scripts/)
# Exit:   0 = every check passed    1 = at least one problem    2 = cannot decide
#
# Layout it expects:
#   channels/<channel>/NNNN-<from>-<type>-<slug>.md     one letter = one file
#   channels/<channel>/INDEX.md                          append-only, one "- NNNN ..." line per letter
#
# What it checks, per channel:
#   1. file names:   NNNN-<from>-<type>-<slug>.md, <type> from the list below
#   2. numbering:    no duplicates (two letters with the same number), no gaps from 0001
#   3. INDEX.md:     exists; every letter appears exactly once; no entry without a letter
#   4. front matter: required keys, seq/type match the file name, date carries a UTC offset,
#                    needs_reply is true|false, replies_to/corrects point at earlier letters,
#                    only an erratum may have corrects != null and an erratum must have it
#   5. immutability: a letter touched by more than one commit is reported (warning, not failure)
#
# It never says "nothing new": it says how many letters in how many channels it looked at,
# or it exits non-zero. A check that cannot go red, or that is always red, carries no signal.
set -u

TYPES='notice-before|notice-after|reply|erratum|closure'
REQUIRED='seq from to type date replies_to corrects needs_reply'

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$ROOT" || { echo "ERROR: cannot enter $ROOT" >&2; exit 2; }

if [ ! -d channels ]; then
  echo "ERROR: no channels/ directory in $ROOT — nothing was checked, refusing to report OK." >&2
  exit 2
fi

# front-matter value for a key; exit 1 when the key (or the front matter) is absent
fm() {
  awk -v k="$1" '
    { sub(/\r$/, "") }
    NR == 1 { if ($0 != "---") exit; next }
    $0 == "---" { exit }
    { i = index($0, ":")
      if (i > 0 && substr($0, 1, i - 1) == k) {
        v = substr($0, i + 1); sub(/[ \t]*#.*$/, "", v); gsub(/^[ \t]+|[ \t]+$/, "", v)
        print v; found = 1; exit
      } }
    END { exit (found ? 0 : 1) }' "$2"
}
# does the file open with a closed front-matter block?
fm_closed() {
  awk '{ sub(/\r$/, "") } NR == 1 { if ($0 != "---") exit 1; next } $0 == "---" { ok = 1; exit } END { exit (ok ? 0 : 1) }' "$1"
}

bad=0; warn=0; nletters=0; nchan=0; inrepo=0
git rev-parse --is-inside-work-tree >/dev/null 2>&1 && inrepo=1
problem() { echo "PROBLEM [$ch] $*"; bad=$((bad + 1)); }

for dir in channels/*/; do
  [ -d "$dir" ] || continue
  ch=$(basename "$dir"); nchan=$((nchan + 1))

  files=(); seqs=()
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [[ ! "$f" =~ ^([0-9]{4})-([A-Za-z0-9_]+)-($TYPES)-.+\.md$ ]]; then
      problem "malformed file name: $f (want NNNN-<from>-<type>-<slug>.md, type one of: ${TYPES//|/, })"
      continue
    fi
    files+=("$f"); seqs+=("${BASH_REMATCH[1]}")
  done < <(LC_ALL=C ls -1 "$dir" | grep -E '^[0-9]{4}-')
  nletters=$((nletters + ${#files[@]}))

  # ---- numbering ----
  if [ "${#seqs[@]}" -gt 0 ]; then
    sorted=$(printf '%s\n' "${seqs[@]}" | sort)
    dups=$(printf '%s\n' "$sorted" | uniq -d | tr '\n' ' ')
    [ -n "$dups" ] && problem "duplicate number(s): $dups— keep the one that reached the remote first, renumber the later one, note it in INDEX.md"
    last=$(printf '%s\n' "$sorted" | tail -1)
    missing=""
    for ((n = 1; n <= 10#$last; n++)); do
      s=$(printf '%04d' "$n")
      printf '%s\n' "$sorted" | grep -qx "$s" || missing="$missing$s "
    done
    [ -n "$missing" ] && problem "missing number(s): ${missing}— a gap means a lost letter; find it before sending anything new"
  fi

  # ---- INDEX.md ----
  idx="$dir/INDEX.md"
  if [ "${#files[@]}" -gt 0 ] && [ ! -f "$idx" ]; then
    problem "has letters but no INDEX.md"
  elif [ -f "$idx" ]; then
    idxseq=$(LC_ALL=C sed -n 's/^- \([0-9][0-9][0-9][0-9]\)\( .*\)\{0,1\}\r\{0,1\}$/\1/p' "$idx" | sort)
    idxdup=$(printf '%s\n' "$idxseq" | uniq -d | sed '/^$/d' | tr '\n' ' ')
    [ -n "$idxdup" ] && problem "INDEX.md lists more than once: ${idxdup}"
    disk=$(printf '%s\n' "${seqs[@]:-}" | sed '/^$/d' | sort -u)
    only_disk=$(comm -23 <(printf '%s\n' "$disk") <(printf '%s\n' "$idxseq" | sed '/^$/d' | sort -u) | tr '\n' ' ')
    only_idx=$(comm -13 <(printf '%s\n' "$disk") <(printf '%s\n' "$idxseq" | sed '/^$/d' | sort -u) | tr '\n' ' ')
    [ -n "$only_disk" ] && problem "letter(s) missing from INDEX.md: ${only_disk}"
    [ -n "$only_idx" ] && problem "INDEX.md entry without a letter: ${only_idx}"
  fi

  # ---- per-letter front matter ----
  for f in "${files[@]:-}"; do
    [ -n "$f" ] || continue
    p="$dir$f"; fseq=${f:0:4}
    [[ "$f" =~ ^[0-9]{4}-[A-Za-z0-9_]+-($TYPES)- ]]; ftype=${BASH_REMATCH[1]}
    if ! fm_closed "$p"; then problem "$f: front matter missing or not closed with ---"; continue; fi
    ok=1
    for k in $REQUIRED; do
      fm "$k" "$p" >/dev/null || { problem "$f: front matter lacks '$k'"; ok=0; }
    done
    [ "$ok" -eq 1 ] || continue
    v_seq=$(fm seq "$p"); v_type=$(fm type "$p"); v_date=$(fm date "$p")
    v_reply=$(fm needs_reply "$p"); v_replies=$(fm replies_to "$p"); v_corr=$(fm corrects "$p")
    [ "$v_seq" = "$fseq" ] || problem "$f: seq '$v_seq' does not match the file name"
    [ "$v_type" = "$ftype" ] || problem "$f: type '$v_type' does not match the file name"
    [[ "$v_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}\ [+-][0-9]{2}:[0-9]{2}$ ]] \
      || problem "$f: date '$v_date' needs the form 'YYYY-MM-DD HH:MM +HH:MM' (UTC offset included)"
    case "$v_reply" in true | false) ;; *) problem "$f: needs_reply must be true or false, got '$v_reply'" ;; esac
    refs=$(printf '%s' "$v_replies" | tr -d '[] ' | tr ',' '\n' | sed '/^$/d')
    for r in $refs; do
      if [[ ! "$r" =~ ^[0-9]{4}$ ]]; then problem "$f: replies_to entry '$r' is not a 4-digit number"
      elif [ $((10#$r)) -ge $((10#$fseq)) ]; then problem "$f: replies_to $r is not an earlier letter"
      elif ! printf '%s\n' "${seqs[@]}" | grep -qx "$r"; then problem "$f: replies_to $r does not exist in this channel"; fi
    done
    if [ "$ftype" = erratum ]; then
      if [[ ! "$v_corr" =~ ^[0-9]{4}$ ]]; then problem "$f: an erratum must set corrects to the letter it corrects, got '$v_corr'"
      elif [ $((10#$v_corr)) -ge $((10#$fseq)) ]; then problem "$f: corrects $v_corr is not an earlier letter"
      elif ! printf '%s\n' "${seqs[@]}" | grep -qx "$v_corr"; then problem "$f: corrects $v_corr does not exist in this channel"; fi
    elif [ "$v_corr" != null ]; then
      problem "$f: only an erratum may set corrects (got '$v_corr'); everything else writes null"
    fi
    if [ "$inrepo" -eq 1 ]; then
      c=$(git log --format=%H -- "$p" 2>/dev/null | wc -l)
      if [ "$c" -gt 1 ]; then echo "WARNING [$ch] $f was changed after it was first committed ($c commits) — sent letters are never edited; write an erratum"; warn=$((warn + 1)); fi
    fi
  done
  echo "channel $ch: ${#files[@]} letter(s)"
done

if [ "$nchan" -eq 0 ]; then
  echo "ERROR: channels/ exists but holds no channel directory — nothing was checked, refusing to report OK." >&2
  exit 2
fi
imm="immutability checked"; [ "$inrepo" -eq 1 ] || imm="immutability check SKIPPED (not a git work tree)"
echo "Checked $nletters letter(s) in $nchan channel(s) under $ROOT/channels/; $imm; $warn warning(s)."
if [ "$bad" -gt 0 ]; then echo "FAILED: $bad problem(s)."; exit 1; fi
echo "OK"
