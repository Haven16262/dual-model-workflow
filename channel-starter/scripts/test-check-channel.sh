#!/usr/bin/env bash
# Tests for check-channel.sh. Everything runs in temporary directories.
# Usage: bash scripts/test-check-channel.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/check-channel.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/test-channel.XXXXXX")
trap 'rm -rf "$T"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

PASS=0; FAIL=0
expect_rc() { # <name> <want rc> <repo> [grep pattern that must appear in the output]
  local out rc
  out=$(bash "$SCRIPT" "$3" 2>&1); rc=$?
  if [ "$rc" = "$2" ] && { [ -z "${4:-}" ] || grep -q -- "$4" <<<"$out"; }; then PASS=$((PASS + 1)); echo "  ok   $1"
  else FAIL=$((FAIL + 1)); echo "  FAIL $1 (rc=$rc, wanted $2${4:+, pattern '$4'})"; echo "$out" | sed 's/^/       | /'; fi
}

# letter <repo> <channel> <seq> <from> <type> <slug> [replies_to] [corrects] [needs_reply]
letter() {
  local d="$1/channels/$2"; mkdir -p "$d"
  cat > "$d/$3-$4-$5-$6.md" <<EOT
---
seq: $3
from: $4
to: other
type: $5
date: 2026-01-01 10:00 +08:00
replies_to: ${7:-[]}
corrects: ${8:-null}
needs_reply: ${9:-false}
---

# $6
EOT
}
index() { # <repo> <channel> <seq...>
  local d="$1/channels/$2"; shift 2; mkdir -p "$d"; : > "$d/INDEX.md"
  for s in "$@"; do echo "- $s example entry" >> "$d/INDEX.md"; done
}
fixture() { local r="$T/$1"; mkdir -p "$r/channels"; echo "$r"; }
good_channel() { # a valid 3-letter channel: 0001 notice, 0002 reply, 0003 erratum of 0001
  letter "$1" demo 0001 alice notice-before first-plan "[]" null true
  letter "$1" demo 0002 bob reply answer "[0001]"
  letter "$1" demo 0003 alice erratum fix-first "[]" 0001
  index "$1" demo 0001 0002 0003
}

echo "== valid channel passes, and reports what it looked at"
R=$(fixture g1); good_channel "$R"
expect_rc "valid channel" 0 "$R" "Checked 3 letter"
echo "== numbering"
R=$(fixture n1); good_channel "$R"; rm "$R"/channels/demo/0002-*; index "$R" demo 0001 0003
expect_rc "gap is reported" 1 "$R" "missing number(s): 0002"
R=$(fixture n2); good_channel "$R"; letter "$R" demo 0002 carol reply dup "[0001]"
expect_rc "duplicate number is reported" 1 "$R" "duplicate number"
R=$(fixture n3); letter "$R" demo 0002 alice notice-before late "[]" null; index "$R" demo 0002
expect_rc "channel that does not start at 0001" 1 "$R" "missing number(s): 0001"
echo "== file names"
R=$(fixture f1); good_channel "$R"; : > "$R/channels/demo/0004-alice-gossip-x.md"
expect_rc "unknown type in file name" 1 "$R" "malformed file name"
R=$(fixture f2); good_channel "$R"; : > "$R/channels/demo/0004-notes.md"
expect_rc "numbered file with the wrong shape" 1 "$R" "malformed file name"
R=$(fixture f3); letter "$R" demo 0001 alice notice-before 中文标题 "[]" null true; index "$R" demo 0001
expect_rc "non-ASCII slug is accepted" 0 "$R" "Checked 1 letter"
echo "== INDEX.md"
R=$(fixture i1); good_channel "$R"; index "$R" demo 0001 0003
expect_rc "letter missing from INDEX" 1 "$R" "missing from INDEX.md: 0002"
R=$(fixture i2); good_channel "$R"; index "$R" demo 0001 0002 0003 0004
expect_rc "INDEX entry without a letter" 1 "$R" "INDEX.md entry without a letter: 0004"
R=$(fixture i3); good_channel "$R"; rm "$R/channels/demo/INDEX.md"
expect_rc "no INDEX.md" 1 "$R" "no INDEX.md"
R=$(fixture i4); good_channel "$R"; index "$R" demo 0001 0002 0002 0003
expect_rc "INDEX lists a number twice" 1 "$R" "more than once"
echo "== front matter"
R=$(fixture m1); good_channel "$R"; sed -i 's/^seq: 0002/seq: 0009/' "$R"/channels/demo/0002-*
expect_rc "seq differs from file name" 1 "$R" "does not match the file name"
R=$(fixture m2); good_channel "$R"; sed -i 's/^date: .*/date: 2026-01-01 10:00/' "$R"/channels/demo/0002-*
expect_rc "date without UTC offset" 1 "$R" "UTC offset"
R=$(fixture m3); good_channel "$R"; sed -i '/^to:/d' "$R"/channels/demo/0002-*
expect_rc "missing required key" 1 "$R" "lacks 'to'"
R=$(fixture m4); good_channel "$R"; sed -i 's/^needs_reply: false/needs_reply: maybe/' "$R"/channels/demo/0002-*
expect_rc "needs_reply not boolean" 1 "$R" "needs_reply must be"
R=$(fixture m5); good_channel "$R"; sed -i 's/^replies_to: .*/replies_to: [0007]/' "$R"/channels/demo/0002-*
expect_rc "replies_to a letter that does not exist" 1 "$R" "replies_to 0007"
R=$(fixture m6); good_channel "$R"; sed -i 's/^replies_to: .*/replies_to: [0003]/' "$R"/channels/demo/0002-*
expect_rc "replies_to a later letter" 1 "$R" "not an earlier letter"
R=$(fixture m7); good_channel "$R"; sed -i 's/^corrects: .*/corrects: null/' "$R"/channels/demo/0003-*
expect_rc "erratum without corrects" 1 "$R" "must set corrects"
R=$(fixture m8); good_channel "$R"; sed -i 's/^corrects: .*/corrects: 0001/' "$R"/channels/demo/0002-*
expect_rc "non-erratum with corrects" 1 "$R" "only an erratum may set corrects"
R=$(fixture m9); good_channel "$R"; sed -i 's/^corrects: .*/corrects: 0042/' "$R"/channels/demo/0003-*
expect_rc "erratum pointing at nothing" 1 "$R" "corrects 0042"
R=$(fixture m10); good_channel "$R"; sed -i '1d' "$R"/channels/demo/0002-*
expect_rc "front matter missing" 1 "$R" "front matter missing or not closed"
R=$(fixture m11); good_channel "$R"; sed -i 's/$/\r/' "$R"/channels/demo/*.md "$R"/channels/demo/INDEX.md
expect_rc "CRLF files (Windows checkout) pass" 0 "$R" "Checked 3 letter"
R=$(fixture m12); good_channel "$R"; sed -i 's/^corrects: null/corrects: null   # no correction/' "$R"/channels/demo/0001-*
expect_rc "trailing comment after a value" 0 "$R"
echo "== cannot decide -> exit 2, never green"
R="$T/e1"; mkdir -p "$R"
expect_rc "no channels/ directory" 2 "$R" "refusing to report OK"
R="$T/e2"; mkdir -p "$R/channels"
expect_rc "channels/ holds no channel" 2 "$R" "refusing to report OK"
expect_rc "repo root that does not exist" 2 "$T/does-not-exist"
echo "== empty channel reports zero rather than silence"
R=$(fixture z1); mkdir -p "$R/channels/new"
expect_rc "channel without letters" 0 "$R" "Checked 0 letter(s) in 1 channel"
echo "== immutability (needs git)"
R=$(fixture w1); good_channel "$R"
(cd "$R" && git init -q -b main && git add -A && git commit -q -m init)
expect_rc "untouched letters: no warning" 0 "$R" "0 warning"
echo "edited later" >> "$R"/channels/demo/0002-bob-reply-answer.md
(cd "$R" && git add -A && git commit -q -m edit)
expect_rc "edited letter is a warning, not a failure" 0 "$R" "was changed after it was first committed"
R=$(fixture w2); good_channel "$R"
expect_rc "outside git the skip is announced" 0 "$R" "SKIPPED"

echo
echo "passed $PASS, failed $FAIL"
[ "$FAIL" -eq 0 ]
