#!/usr/bin/env bash
#
# run.sh — regression tests for the kabeuchi helper scripts.
#
# Zero dependencies beyond git + bash: each test writes small text blobs to a
# temp dir, runs one script, and asserts on its stdout and exit code. Run from
# anywhere:  bash tests/run.sh
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${HERE}/../scripts"
NORMALIZE="${SCRIPTS}/normalize.sh"
MERGE3="${SCRIPTS}/merge3.sh"
MARK="${SCRIPTS}/mark.sh"
PROMPT_HOOK="${SCRIPTS}/prompt-hook.sh"

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }

# assert_eq <label> <expected> <actual>
assert_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected [$2], got [$3])"; fi
}

echo "normalize.sh"
{
  # CRLF -> LF, and the trailing newline is stripped.
  out="$(printf 'a\r\nb\r\n' | bash "$NORMALIZE")"
  assert_eq "CRLF becomes LF, trailing newline stripped" "$(printf 'a\nb')" "$out"

  # Trailing blank lines collapse away entirely.
  out="$(printf 'hello\n\n\n' | bash "$NORMALIZE")"
  assert_eq "trailing newlines stripped" "hello" "$out"

  # Trailing spaces/tabs at the very end of the body are stripped.
  out="$(printf 'hello \t ' | bash "$NORMALIZE")"
  assert_eq "trailing spaces/tabs stripped" "hello" "$out"

  # Interior blank lines are preserved — only the END of the body is trimmed.
  out="$(printf 'a\n\nb\n' | bash "$NORMALIZE")"
  assert_eq "interior blank line preserved" "$(printf 'a\n\nb')" "$out"

  # The core GitHub scenario: our own write has no trailing newline, GitHub's
  # read-back appends one. Both must normalize to the SAME text (else every
  # check after our own write would look like an external "conflict").
  ours="$(printf 'spec body' | bash "$NORMALIZE")"
  github="$(printf 'spec body\n' | bash "$NORMALIZE")"
  assert_eq "GitHub's appended newline is not seen as a change" "$ours" "$github"

  # Normalization is idempotent.
  once="$(printf 'x\r\n\r\n' | bash "$NORMALIZE")"
  twice="$(printf '%s' "$once" | bash "$NORMALIZE")"
  assert_eq "normalization is idempotent" "$once" "$twice"

  # A missing file argument is a usage error.
  rc=0; bash "$NORMALIZE" /no/such/file >/dev/null 2>&1 || rc=$?
  assert_eq "missing file exits 2" "2" "$rc"
}

echo "mark.sh"
{
  d="$(mktemp -d)"
  export KABEUCHI_DIR="$d/marks"
  unset CLAUDE_CODE_SESSION_ID CLAUDE_SESSION_ID
  SID="3186bc75-4165-4b4d-bc2c-a4b5d697a9f6"

  # The target arrives on stdin, and the marker is one line naming it.
  printf 'https://github.com/o/r/issues/9' | bash "$MARK" set "$SID" >/dev/null 2>&1
  assert_eq "set writes the target from stdin" "https://github.com/o/r/issues/9" "$(head -n 1 "$KABEUCHI_DIR/$SID" 2>/dev/null)"

  # Success is silent: the injected !`...` block must contribute no text.
  out="$(printf 'x' | bash "$MARK" set "$SID" 2>&1)"
  assert_eq "set prints nothing on success" "" "$out"

  # A target may also be passed as an argument (Phase 1 refreshes it that way).
  bash "$MARK" set "$SID" "docs/spec.md" >/dev/null 2>&1
  assert_eq "set accepts the target as an argument" "docs/spec.md" "$(head -n 1 "$KABEUCHI_DIR/$SID" 2>/dev/null)"

  # An empty target still marks the session — a bar reading "in progress" with a
  # placeholder beats no second row at all.
  printf '' | bash "$MARK" set "$SID" >/dev/null 2>&1
  assert_eq "empty target falls back to a placeholder" "(resolving target)" "$(head -n 1 "$KABEUCHI_DIR/$SID" 2>/dev/null)"

  # Newlines and control characters would corrupt a single-row status line.
  printf 'first line\nsecond line' | bash "$MARK" set "$SID" >/dev/null 2>&1
  assert_eq "multi-line target collapses to its first line" "first line" "$(head -n 1 "$KABEUCHI_DIR/$SID" 2>/dev/null)"
  assert_eq "the target occupies exactly one line" "1" "$(awk 'END{print NR}' <<< "$(head -n 1 "$KABEUCHI_DIR/$SID")")"

  printf 'a\tb\033[31mred' | bash "$MARK" set "$SID" >/dev/null 2>&1
  assert_eq "control characters are stripped" "ab[31mred" "$(head -n 1 "$KABEUCHI_DIR/$SID" 2>/dev/null)"

  printf '   padded   ' | bash "$MARK" set "$SID" >/dev/null 2>&1
  assert_eq "surrounding whitespace is trimmed" "padded" "$(head -n 1 "$KABEUCHI_DIR/$SID" 2>/dev/null)"

  # An over-long target would wrap the bar onto a third row.
  printf '%0.sx' $(seq 1 500) | bash "$MARK" set "$SID" >/dev/null 2>&1
  assert_eq "target is capped at 200 characters" "200" "$(awk 'NR==1{print length($0)}' "$KABEUCHI_DIR/$SID")"

  # clear removes it; the status line then drops back to one row.
  bash "$MARK" set "$SID" "t" >/dev/null 2>&1
  bash "$MARK" clear "$SID" >/dev/null 2>&1
  if [ -e "$KABEUCHI_DIR/$SID" ]; then bad "clear removes the marker"; else ok "clear removes the marker"; fi

  # Clearing a session that was never marked is not an error.
  rc=0; bash "$MARK" clear "$SID" >/dev/null 2>&1 || rc=$?
  assert_eq "clear on a missing marker exits 0" "0" "$rc"

  # Markers are per session, so one session never disturbs another.
  OTHER="aaaaaaaa-0000-0000-0000-000000000000"
  bash "$MARK" set "$SID" "mine" >/dev/null 2>&1
  bash "$MARK" set "$OTHER" "theirs" >/dev/null 2>&1
  bash "$MARK" clear "$OTHER" >/dev/null 2>&1
  assert_eq "clearing one session leaves the other marked" "mine" "$(head -n 1 "$KABEUCHI_DIR/$SID" 2>/dev/null)"

  # The session id becomes a filename, so a traversal attempt must not write out
  # of the marker directory.
  bash "$MARK" set "../escaped" "x" >/dev/null 2>&1
  if [ -e "$d/escaped" ] || [ -e "$KABEUCHI_DIR/../escaped" ]; then
    bad "a traversing session id must not escape the marker dir"
  else
    ok "a traversing session id must not escape the marker dir"
  fi

  # THE CRITICAL PROPERTY: a non-zero exit from an injected command aborts the
  # whole /kabeuchi invocation, so every path here must exit 0.
  for bad_call in "set" "clear" "path" "bogus-action" "set ../nope" "clear /etc/passwd"; do
    rc=0
    # shellcheck disable=SC2086
    bash "$MARK" $bad_call </dev/null >/dev/null 2>&1 || rc=$?
    assert_eq "exits 0 for: mark.sh $bad_call" "0" "$rc"
  done
  rc=0; bash "$MARK" </dev/null >/dev/null 2>&1 || rc=$?
  assert_eq "exits 0 for: mark.sh (no arguments)" "0" "$rc"

  # An unwritable marker directory must still not fail the invocation.
  rc=0; KABEUCHI_DIR=/proc/nonexistent/nope bash "$MARK" set "$SID" "x" </dev/null >/dev/null 2>&1 || rc=$?
  assert_eq "exits 0 when the marker dir cannot be created" "0" "$rc"

  # The session id falls back to the environment variable Claude Code exports.
  bash "$MARK" clear "$SID" >/dev/null 2>&1
  CLAUDE_CODE_SESSION_ID="$SID" bash "$MARK" set "" "from-env" >/dev/null 2>&1
  assert_eq "session id falls back to \$CLAUDE_CODE_SESSION_ID" "from-env" "$(head -n 1 "$KABEUCHI_DIR/$SID" 2>/dev/null)"

  # ...and, failing that, to the session_id in hook JSON on stdin.
  bash "$MARK" clear "$SID" >/dev/null 2>&1
  bash "$MARK" set "$SID" "x" >/dev/null 2>&1
  printf '{"session_id":"%s","hook_event_name":"SessionEnd","reason":"other"}' "$SID" | bash "$MARK" clear >/dev/null 2>&1
  if [ -e "$KABEUCHI_DIR/$SID" ]; then
    bad "clear reads the session id from hook JSON on stdin"
  else
    ok "clear reads the session id from hook JSON on stdin"
  fi

  # A marker outliving its session is swept, so the directory cannot grow forever.
  bash "$MARK" set "$SID" "current" >/dev/null 2>&1
  STALE="bbbbbbbb-0000-0000-0000-000000000000"
  printf 'ancient\n' > "$KABEUCHI_DIR/$STALE"
  touch -t 200001010000 "$KABEUCHI_DIR/$STALE"
  bash "$MARK" set "$SID" "current" >/dev/null 2>&1
  if [ -e "$KABEUCHI_DIR/$STALE" ]; then bad "a stale marker is swept"; else ok "a stale marker is swept"; fi
  assert_eq "the sweep spares the current marker" "current" "$(head -n 1 "$KABEUCHI_DIR/$SID" 2>/dev/null)"

  # The owning process is recorded so a session that dies without clearing its
  # marker still gets collected — the case no session-end hook can cover.
  CLAUDE_PID=$$ bash "$MARK" set "$SID" "owned" >/dev/null 2>&1
  assert_eq "the owning pid is recorded on line 2" "pid=$$" "$(sed -n 2p "$KABEUCHI_DIR/$SID")"
  assert_eq "recording the pid leaves line 1 alone" "owned" "$(head -n 1 "$KABEUCHI_DIR/$SID")"

  # A live owner must survive the sweep...
  CLAUDE_PID=$$ bash "$MARK" set "$OTHER" "other-live" >/dev/null 2>&1
  assert_eq "a marker whose owner is alive survives the sweep" "owned" "$(head -n 1 "$KABEUCHI_DIR/$SID" 2>/dev/null)"

  # ...and a dead one must not. Spawn a process, reap it, then reuse its pid.
  DEAD="cccccccc-0000-0000-0000-000000000000"
  ( exit 0 ) & dead_pid=$!; wait "$dead_pid" 2>/dev/null
  printf 'orphaned\npid=%s\n' "$dead_pid" > "$KABEUCHI_DIR/$DEAD"
  CLAUDE_PID=$$ bash "$MARK" set "$SID" "owned" >/dev/null 2>&1
  if [ -e "$KABEUCHI_DIR/$DEAD" ]; then
    bad "a marker whose owner has exited is swept"
  else
    ok "a marker whose owner has exited is swept"
  fi

  # A marker with no pid line is left to the age sweep, not dropped immediately.
  NOPID="dddddddd-0000-0000-0000-000000000000"
  printf 'no-owner-recorded\n' > "$KABEUCHI_DIR/$NOPID"
  CLAUDE_PID=$$ bash "$MARK" set "$SID" "owned" >/dev/null 2>&1
  if [ -e "$KABEUCHI_DIR/$NOPID" ]; then
    ok "a recent marker with no pid line is kept"
  else
    bad "a recent marker with no pid line is kept"
  fi

  unset KABEUCHI_DIR
  rm -rf "$d"
}

echo "prompt-hook.sh"
{
  d="$(mktemp -d)"
  export KABEUCHI_DIR="$d/marks"
  SID="3186bc75-4165-4b4d-bc2c-a4b5d697a9f6"
  hook_json="$(printf '{"session_id":"%s","hook_event_name":"UserPromptSubmit","prompt":"hi"}' "$SID")"

  # No marker -> the hook is silent, so a session that never ran kabeuchi pays
  # nothing for the hook staying registered.
  out="$(printf '%s' "$hook_json" | bash "$PROMPT_HOOK" 2>&1)"
  assert_eq "silent when the session has no marker" "" "$out"

  bash "$MARK" set "$SID" "https://github.com/o/r/issues/9" >/dev/null 2>&1
  out="$(printf '%s' "$hook_json" | bash "$PROMPT_HOOK" 2>&1)"
  assert_eq "names the target verbatim, and restates both rules" \
    "kabeuchi in progress. Target: https://github.com/o/r/issues/9. Ask one question at a time. Write each settled point back into the target in place." \
    "$out"

  # A UserPromptSubmit hook that exits non-zero swallows the user's prompt, so
  # this one must exit 0 no matter what it is handed.
  for payload in "$hook_json" "{}" "not json at all" ""; do
    rc=0; printf '%s' "$payload" | bash "$PROMPT_HOOK" >/dev/null 2>&1 || rc=$?
    assert_eq "exits 0 for payload: ${payload:-(empty)}" "0" "$rc"
  done

  # Another session's marker must not leak into this one.
  out="$(printf '{"session_id":"aaaaaaaa-0000-0000-0000-000000000000"}' | bash "$PROMPT_HOOK" 2>&1)"
  assert_eq "another session's marker does not leak in" "" "$out"

  unset KABEUCHI_DIR
  rm -rf "$d"
}

echo "merge3.sh"
{
  d="$(mktemp -d)"
  printf 'Line A\nLine B\nLine C\n'        > "$d/base"
  printf 'Line A EDITED\nLine B\nLine C\n' > "$d/theirs"
  printf 'Line A\nLine B\nLine C EDITED\n' > "$d/mine"

  out="$(bash "$MERGE3" "$d/base" "$d/mine" "$d/theirs")" && rc=0 || rc=$?
  assert_eq "disjoint edits merge cleanly -> exit 0" "0" "$rc"
  case "$out" in
    *"Line A EDITED"*) ok "clean merge keeps their edit" ;;
    *) bad "clean merge dropped their edit (got: $out)" ;;
  esac
  case "$out" in
    *"Line C EDITED"*) ok "clean merge keeps my edit" ;;
    *) bad "clean merge dropped my edit (got: $out)" ;;
  esac
  case "$out" in
    *"<<<<<<<"*) bad "clean merge must not contain conflict markers" ;;
    *) ok "clean merge has no conflict markers" ;;
  esac

  # Overlapping edits to the same line must NOT auto-resolve.
  printf 'shared line\n'   > "$d/base2"
  printf 'their version\n' > "$d/theirs2"
  printf 'my version\n'    > "$d/mine2"
  out="$(bash "$MERGE3" "$d/base2" "$d/mine2" "$d/theirs2")" && rc=0 || rc=$?
  assert_eq "overlapping edits conflict -> exit 1" "1" "$rc"
  case "$out" in
    *"<<<<<<<"*">>>>>>>"*) ok "conflict output carries markers" ;;
    *) bad "conflict output missing markers (got: $out)" ;;
  esac

  # Usage errors.
  rc=0; bash "$MERGE3" "$d/base" "$d/mine" >/dev/null 2>&1 || rc=$?
  assert_eq "wrong arg count exits 2" "2" "$rc"
  rc=0; bash "$MERGE3" "$d/base" "$d/mine" /no/such/file >/dev/null 2>&1 || rc=$?
  assert_eq "missing input file exits 2" "2" "$rc"

  rm -rf "$d"
}

echo "merge3.sh (leaves no temp litter in the working directory)"
{
  # The bug this guards against: the old inline flow wrote mine/base/theirs/
  # merged files into the caller's working tree and never cleaned them up.
  work="$(mktemp -d)"
  printf 'a\n' > "$work/base"; printf 'a\n' > "$work/mine"; printf 'a\n' > "$work/theirs"
  # find, not ls: ls output is not safe to parse for arbitrary filenames (SC2012).
  list_dir() { find "$1" -mindepth 1 -maxdepth 1 -exec basename {} \; | sort | tr '\n' ' '; }
  before="$(list_dir "$work")"
  ( cd "$work" && bash "$MERGE3" base mine theirs >/dev/null 2>&1 )
  after="$(list_dir "$work")"
  assert_eq "merge leaves no extra files in CWD" "$before" "$after"
  rm -rf "$work"
}

echo
printf 'total: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
