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

  # THE SWEEP DELETES FILES, and KABEUCHI_DIR is caller-settable: point it at a
  # directory holding anything else and an unscoped age sweep would take that
  # too. Only session-id shaped names may ever be collected.
  for stranger in "settings.json" "CLAUDE.md" "notes"; do
    printf 'not a marker\n' > "$KABEUCHI_DIR/$stranger"
    touch -t 200001010000 "$KABEUCHI_DIR/$stranger"
  done
  # A stranger carrying a dead pid on line 2 must survive the pid sweep as well.
  ( exit 0 ) & stranger_pid=$!; wait "$stranger_pid" 2>/dev/null
  printf 'not a marker\npid=%s\n' "$stranger_pid" > "$KABEUCHI_DIR/config.toml"
  CLAUDE_PID=$$ bash "$MARK" set "$SID" "owned" >/dev/null 2>&1
  survived=true
  for stranger in "settings.json" "CLAUDE.md" "notes" "config.toml"; do
    [ -e "$KABEUCHI_DIR/$stranger" ] || survived=false
  done
  assert_eq "a non-marker file in the marker dir is never swept" "true" "$survived"

  # The SessionEnd hook in the user's settings.json finds this script by path and
  # greps for the marker before running it, because the thing it runs it for is a
  # deletion. Losing the marker silently disables that cleanup.
  if grep -q "kabeuchi-mark-sh" "$MARK"; then
    ok "mark.sh carries the marker the SessionEnd hook greps for"
  else
    bad "mark.sh carries the marker the SessionEnd hook greps for"
  fi

  unset KABEUCHI_DIR
  rm -rf "$d"
}

echo "SKILL.md (injected command)"
{
  SKILL_MD="${HERE}/../SKILL.md"

  # $ARGUMENTS is substituted as text into the injected command line before the
  # shell parses it, so the user's target would arrive as shell syntax — and no
  # quoting construct saves it, because the construct's own terminator is part
  # of that text (a quoted heredoc ends early on a target containing its
  # delimiter, and the rest runs as commands). The marker is seeded with a
  # placeholder and Phase 1 fills in the real target instead.
  block="$(awk '/^```!$/{f=1;next} f&&/^```$/{f=0} f' "$SKILL_MD")"

  case "$block" in
    "") bad "an injected command block exists in SKILL.md" ;;
    *)  ok  "an injected command block exists in SKILL.md" ;;
  esac
  case "$block" in
    *\$ARGUMENTS*) bad "the injected command must not interpolate \$ARGUMENTS" ;;
    *)             ok  "the injected command does not interpolate \$ARGUMENTS" ;;
  esac
  case "$block" in
    *"mark.sh set"*) ok  "the injected command still seeds the session marker" ;;
    *)               bad "the injected command still seeds the session marker" ;;
  esac

  # Phase 1 refreshes the marker with the resolved target. Double quotes there
  # would make a target containing $(...) or a backtick command substitution,
  # and the command matches the Bash(.../mark.sh *) rule in allowed-tools, so it
  # can be pre-approved and run unasked. Single quotes expand nothing.
  refresh="$(grep -F "mark.sh set \${CLAUDE_SESSION_ID} " "$SKILL_MD" | grep -v '^```')"
  case "$refresh" in
    "")   bad "SKILL.md documents a marker refresh call" ;;
    *'"'*) bad "the marker refresh must not double-quote the target" ;;
    *)    ok  "the marker refresh single-quotes the target" ;;
  esac
}

echo "SKILL.md (UserPromptSubmit hook command)"
{
  SKILL_MD="${HERE}/../SKILL.md"
  hook_cmd="$(sed -n "s/^ *command: '\(.*\)'$/\1/p" "$SKILL_MD" | head -n 1)"

  case "$hook_cmd" in
    "") bad "the frontmatter registers a hook command" ;;
    *)  ok  "the frontmatter registers a hook command" ;;
  esac

  # The hook locates the script by path, and $CLAUDE_PLUGIN_ROOT is read fresh
  # from the environment every turn. Verify identity before executing.
  case "$hook_cmd" in
    *"grep -q kabeuchi-prompt-hook"*) ok  "the hook verifies the script's identity before running it" ;;
    *)                                bad "the hook verifies the script's identity before running it" ;;
  esac
  # :+ yields nothing when the variable is unset. :- would resolve the candidate
  # to /scripts/prompt-hook.sh or /.claude/skills/..., at the filesystem root.
  for var in CLAUDE_PLUGIN_ROOT CLAUDE_PROJECT_DIR; do
    case "$hook_cmd" in
      *"$var:-"*) bad "an unset $var yields no candidate path (uses :-)" ;;
      *"$var:+"*) ok  "an unset $var yields no candidate path" ;;
      *)          bad "an unset $var yields no candidate path" ;;
    esac
  done
  # Every install location is searched: both readings of the plugin root (the
  # documented plugin dir and the skill dir it has been observed to hold), the
  # project checkout, and the personal install.
  for frag in "CLAUDE_PLUGIN_ROOT/skills/kabeuchi/scripts/prompt-hook.sh" \
              "CLAUDE_PLUGIN_ROOT/scripts/prompt-hook.sh" \
              ".claude/skills/kabeuchi/scripts/prompt-hook.sh"; do
    case "$hook_cmd" in
      *"$frag"*) ok  "the hook looks for .../$frag" ;;
      *)         bad "the hook looks for .../$frag" ;;
    esac
  done
  # Order, not just presence: a repository supplies the $CLAUDE_PROJECT_DIR
  # candidate, so the personal install has to be offered the turn first. The
  # identity marker is a published string and cannot settle a deliberate
  # collision; being asked first is what does.
  # The `$`-names below are literal text inside the hook command being matched,
  # not variables this script wants expanded.
  # shellcheck disable=SC2016
  case "$hook_cmd" in
    *'$HOME/.claude/skills/kabeuchi/scripts/prompt-hook.sh'*'$CLAUDE_PROJECT_DIR/.claude/skills'*)
      ok  "the personal install is tried before the project checkout" ;;
    *)
      bad "the personal install is tried before the project checkout" ;;
  esac
  if grep -q "kabeuchi-prompt-hook" "$PROMPT_HOOK"; then
    ok "prompt-hook.sh still carries the marker the hook greps for"
  else
    bad "prompt-hook.sh still carries the marker the hook greps for"
  fi

  # ── Run the hook command for real, with every candidate under our control. ──
  # CLAUDE_PROJECT_DIR is set explicitly in each run (empty where the case needs
  # it absent) so that a real one in the ambient environment cannot leak in.
  d="$(mktemp -d)"
  plugin="$d/plugin/skills/kabeuchi/scripts"
  project="$d/project/.claude/skills/kabeuchi/scripts"
  mkdir -p "$plugin" "$project" "$d/home/.claude/kabeuchi"
  SID="3186bc75-4165-4b4d-bc2c-a4b5d697a9f6"
  printf 'docs/spec.md\n' > "$d/home/.claude/kabeuchi/$SID"
  run_hook() { # run_hook <plugin_root> <project_dir>
    CLAUDE_PLUGIN_ROOT="$1" CLAUDE_PROJECT_DIR="$2" HOME="$d/home" \
      CLAUDE_CODE_SESSION_ID="$SID" KABEUCHI_DIR="$d/home/.claude/kabeuchi" \
      sh -c "$hook_cmd" 2>&1
  }

  # A decoy at the same relative path under each root: right path, wrong script.
  for decoy in "$plugin" "$project"; do
    printf '#!/bin/sh\necho DECOY-RAN\n' > "$decoy/prompt-hook.sh"
    chmod +x "$decoy/prompt-hook.sh"
  done
  out="$(run_hook "$d/plugin" "$d/project")"; rc=$?
  assert_eq "a same-path script under a foreign plugin/project root is not executed" "" "$out"
  assert_eq "the hook still exits 0 when nothing is runnable" "0" "$rc"

  # The project checkout alone: this is the case the candidate list was extended
  # for — a kabeuchi committed to .claude/skills/ with no plugin and no install.
  rm -f "$plugin/prompt-hook.sh"
  cp "$PROMPT_HOOK" "$project/prompt-hook.sh"
  out="$(run_hook "" "$d/project")"
  case "$out" in
    "kabeuchi in progress. Target: docs/spec.md."*) ok "a project-local .claude/skills copy is found" ;;
    *) bad "a project-local .claude/skills copy is found (got: $out)" ;;
  esac

  # The skill-dir reading of the plugin root also resolves, since that is what a
  # skill-registered hook has been observed to get.
  rm -f "$project/prompt-hook.sh"
  mkdir -p "$d/plugin-as-skill/scripts"
  cp "$PROMPT_HOOK" "$d/plugin-as-skill/scripts/prompt-hook.sh"
  out="$(run_hook "$d/plugin-as-skill" "")"
  case "$out" in
    "kabeuchi in progress. Target: docs/spec.md."*) ok "a plugin root pointing at the skill dir also resolves" ;;
    *) bad "a plugin root pointing at the skill dir also resolves (got: $out)" ;;
  esac
  cp "$PROMPT_HOOK" "$project/prompt-hook.sh"

  # Both present: the plugin root wins, mirroring skill resolution precedence.
  # The project copy is made distinguishable while keeping the identity marker.
  sed 's/kabeuchi in progress\./FROM-PROJECT./' "$PROMPT_HOOK" > "$project/prompt-hook.sh"
  chmod +x "$project/prompt-hook.sh"
  cp "$PROMPT_HOOK" "$plugin/prompt-hook.sh"
  out="$(run_hook "$d/plugin" "$d/project")"
  case "$out" in
    "kabeuchi in progress. Target: docs/spec.md."*) ok "the plugin root is preferred over the project checkout" ;;
    *) bad "the plugin root is preferred over the project checkout (got: $out)" ;;
  esac

  # And the personal install is preferred over the project checkout — the one
  # place this deviates from Claude Code's own precedence, because the project
  # candidate is the only one a cloned repository can supply.
  rm -f "$plugin/prompt-hook.sh"
  mkdir -p "$d/home/.claude/skills/kabeuchi/scripts"
  cp "$PROMPT_HOOK" "$d/home/.claude/skills/kabeuchi/scripts/prompt-hook.sh"
  out="$(run_hook "" "$d/project")"
  case "$out" in
    "kabeuchi in progress. Target: docs/spec.md."*) ok "the personal install is preferred over the project checkout" ;;
    *) bad "the personal install is preferred over the project checkout (got: $out)" ;;
  esac

  # A planted copy carrying the marker still loses to the personal install: the
  # marker is a published string, so ordering is what decides this, not identity.
  out="$(run_hook "" "$d/project")"
  case "$out" in
    "FROM-PROJECT."*) bad "a marker-carrying project copy cannot displace the personal install" ;;
    *) ok "a marker-carrying project copy cannot displace the personal install" ;;
  esac

  # With no plugin and no personal install, the project checkout still answers.
  rm -f "$d/home/.claude/skills/kabeuchi/scripts/prompt-hook.sh"
  out="$(run_hook "" "$d/project")"
  case "$out" in
    "FROM-PROJECT. Target: docs/spec.md."*) ok "the project checkout is the last resort" ;;
    *) bad "the project checkout is the last resort (got: $out)" ;;
  esac
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
