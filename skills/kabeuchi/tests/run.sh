#!/usr/bin/env bash
#
# run.sh — regression tests for the kabeuchi helper scripts.
#
# Zero dependencies beyond git, bash, and standard tools (sed, tr, head): each
# test writes small text blobs to a temp dir, runs one script, and asserts on
# its stdout and exit code. Run from anywhere:  bash tests/run.sh
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="${HERE}/../scripts"
NORMALIZE="${SCRIPTS}/normalize.sh"
MERGE3="${SCRIPTS}/merge3.sh"
MARK="${SCRIPTS}/mark.sh"
PROMPT_HOOK="${SCRIPTS}/prompt-hook.sh"
STATUSLINE="${SCRIPTS}/statusline.sh"
TALLY="${SCRIPTS}/tally.sh"
GRILLED="${SCRIPTS}/grilled-line.sh"

pass=0
fail=0
skipped=0
ok()   { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad()  { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }
skip() { printf '  skip %s\n' "$1"; skipped=$((skipped + 1)); }

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
  # The project checkout is the one candidate a cloned repository can supply, and
  # running it unattended on every prompt is broader trust than editing a
  # markdown target needs — so it is behind an explicit opt-in, not merely last.
  # The `$`-names below are literal text inside the hook command being matched,
  # not variables this script wants expanded.
  # shellcheck disable=SC2016
  case "$hook_cmd" in
    *'KABEUCHI_ALLOW_PROJECT_HOOK'*'$CLAUDE_PROJECT_DIR/.claude/skills'*)
      ok  "the project checkout candidate is gated on KABEUCHI_ALLOW_PROJECT_HOOK" ;;
    *)
      bad "the project checkout candidate is gated on KABEUCHI_ALLOW_PROJECT_HOOK" ;;
  esac
  # The gate wants an affirmative value, not merely a non-empty one: with :+ a
  # stray KABEUCHI_ALLOW_PROJECT_HOOK=0 would switch the candidate on.
  # shellcheck disable=SC2016
  case "$hook_cmd" in
    *'case "${KABEUCHI_ALLOW_PROJECT_HOOK:-}" in 1|true|yes)'*)
      ok  "the opt-in matches affirmative values only" ;;
    *)
      bad "the opt-in matches affirmative values only" ;;
  esac
  # Order within the search loop itself: the personal install is offered the turn
  # before the project checkout even when the opt-in is on. The identity marker is
  # a published string and cannot settle a deliberate collision; being asked first
  # is what does.
  loop_list="${hook_cmd#*for c in }"
  # shellcheck disable=SC2016
  case "$loop_list" in
    *'$HOME/.claude/skills/kabeuchi/scripts/prompt-hook.sh'*'"$p"'*)
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
  # The third argument is KABEUCHI_ALLOW_PROJECT_HOOK: empty (the default) means
  # the project checkout candidate is never even assembled.
  run_hook() { # run_hook <plugin_root> <project_dir> [allow_project]
    CLAUDE_PLUGIN_ROOT="$1" CLAUDE_PROJECT_DIR="$2" HOME="$d/home" \
      KABEUCHI_ALLOW_PROJECT_HOOK="${3:-}" \
      CLAUDE_CODE_SESSION_ID="$SID" KABEUCHI_DIR="$d/home/.claude/kabeuchi" \
      sh -c "$hook_cmd" 2>&1
  }

  # A decoy at the same relative path under each root: right path, wrong script.
  for decoy in "$plugin" "$project"; do
    printf '#!/bin/sh\necho DECOY-RAN\n' > "$decoy/prompt-hook.sh"
    chmod +x "$decoy/prompt-hook.sh"
  done
  out="$(run_hook "$d/plugin" "$d/project" 1)"; rc=$?
  assert_eq "a same-path script under a foreign plugin/project root is not executed" "" "$out"
  assert_eq "the hook still exits 0 when nothing is runnable" "0" "$rc"

  # The project checkout alone, opted in: this is the case the candidate list was
  # extended for — a kabeuchi committed to .claude/skills/ with no plugin and no
  # personal install.
  rm -f "$plugin/prompt-hook.sh"
  cp "$PROMPT_HOOK" "$project/prompt-hook.sh"
  out="$(run_hook "" "$d/project" 1)"
  case "$out" in
    "kabeuchi in progress. Target: docs/spec.md."*) ok "a project-local .claude/skills copy is found when opted in" ;;
    *) bad "a project-local .claude/skills copy is found when opted in (got: $out)" ;;
  esac

  # ...and the same setup stays silent without the opt-in. This is the whole
  # point of the gate: a cloned repository's script is not executed unattended.
  out="$(run_hook "" "$d/project")"; rc=$?
  assert_eq "a project-local copy is NOT executed by default" "" "$out"
  assert_eq "the hook still exits 0 when the project candidate is gated off" "0" "$rc"
  for val in 0 "" no maybe; do
    out="$(run_hook "" "$d/project" "$val")"
    assert_eq "KABEUCHI_ALLOW_PROJECT_HOOK=${val:-(empty)} does not enable the project candidate" "" "$out"
  done
  for val in 1 true yes; do
    out="$(run_hook "" "$d/project" "$val")"
    case "$out" in
      "kabeuchi in progress. Target: docs/spec.md."*) ok "KABEUCHI_ALLOW_PROJECT_HOOK=$val enables the project candidate" ;;
      *) bad "KABEUCHI_ALLOW_PROJECT_HOOK=$val enables the project candidate (got: $out)" ;;
    esac
  done

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
  out="$(run_hook "$d/plugin" "$d/project" 1)"
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
  out="$(run_hook "" "$d/project" 1)"
  case "$out" in
    "kabeuchi in progress. Target: docs/spec.md."*) ok "the personal install is preferred over the project checkout" ;;
    *) bad "the personal install is preferred over the project checkout (got: $out)" ;;
  esac

  # A planted copy carrying the marker still loses to the personal install, even
  # with the opt-in on: the marker is a published string, so ordering is what
  # decides this, not identity.
  out="$(run_hook "" "$d/project" 1)"
  case "$out" in
    "FROM-PROJECT."*) bad "a marker-carrying project copy cannot displace the personal install" ;;
    *) ok "a marker-carrying project copy cannot displace the personal install" ;;
  esac

  # With no plugin and no personal install, the opted-in project checkout answers.
  rm -f "$d/home/.claude/skills/kabeuchi/scripts/prompt-hook.sh"
  out="$(run_hook "" "$d/project" 1)"
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
    "kabeuchi in progress. Target: https://github.com/o/r/issues/9. Ask one question at a time. Put each recommendation to a kabeuchi-voter vote before showing it. Write each settled point back into the target in place." \
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

echo "statusline.sh"
{
  d="$(mktemp -d)"
  export KABEUCHI_DIR="$d/marks"
  mkdir -p "$KABEUCHI_DIR" "$d/home"
  SID="3186bc75-4165-4b4d-bc2c-a4b5d697a9f6"
  E=$'\e'
  A=$'\a'
  GH="https://github.com"
  # sl <session_id>: the status line's stdout and stderr for that session.
  sl() { printf '{"session_id":"%s","model":{"display_name":"Opus"}}' "$1" | HOME="$d/home" bash "$STATUSLINE" 2>&1; }
  # marker <first line>: write the marker by hand, bypassing mark.sh's
  # sanitizing, so the script's own hardening is what is tested.
  marker() { printf '%s\npid=1\n' "$1" > "$KABEUCHI_DIR/$SID"; }
  # link <owner/repo#n text> <url>: the line for a linked issue target.
  link() { printf 'kabeuchi in progress · %s]8;;%s%s%s%s]8;;%s' "$E" "$2" "$A" "$1" "$E" "$A"; }

  assert_eq "silent when the session has no marker" "" "$(sl "$SID")"

  marker "$GH/gipcompany/skills/issues/52"
  assert_eq "an issue URL is OWNER/REPO#N in an OSC 8 link ending in BEL" \
    "$(link "gipcompany/skills#52" "$GH/gipcompany/skills/issues/52")" "$(sl "$SID")"

  marker "$GH/o/r/issues/9#issuecomment-123"
  assert_eq "a fragment is dropped from the link" "$(link "o/r#9" "$GH/o/r/issues/9")" "$(sl "$SID")"
  marker "$GH/o/r/issues/9/?q=1"
  assert_eq "a trailing /... or ?... is dropped from the link" "$(link "o/r#9" "$GH/o/r/issues/9")" "$(sl "$SID")"

  marker "$GH/o/r/issues/007"
  assert_eq "leading zeros are dropped" "$(link "o/r#7" "$GH/o/r/issues/7")" "$(sl "$SID")"

  # Anything the regex does not accept is the target as plain text, with no
  # escape sequence at all.
  for t in "$GH/o/issues/9" "$GH/../r/issues/9" "$GH/o/../issues/9" "$GH/o/./issues/9" \
           "$GH/o/r/x/issues/9" "$GH/o/r/issues/0" "$GH/o/r/issues/9x" "$GH/-o/r/issues/9" \
           "http://github.com/o/r/issues/9" "https://github.com.evil/o/r/issues/9" "$GH/o/r/pull/9"; do
    marker "$t"
    assert_eq "plain text: $t" "kabeuchi in progress · $t" "$(sl "$SID")"
  done

  # Control bytes are stripped even though mark.sh strips them too, so an
  # embedded OSC 8 cannot open a link of its own: what is left is plain text.
  marker "$GH/o/r/issues/9${E}]8;;https://evil.example${A}click${E}]8;;${A}"
  out="$(sl "$SID")"
  assert_eq "an embedded OSC 8 is defused to plain text" \
    "kabeuchi in progress · $GH/o/r/issues/9]8;;https://evil.exampleclick]8;;" "$out"
  case "$out" in *"$E"* | *"$A"*) bad "no ESC or BEL survives from the marker" ;; *) ok "no ESC or BEL survives from the marker" ;; esac
  marker "notes/${E}[31mred$(printf '\001\177')spec.md"
  assert_eq "control bytes are stripped from a path" "kabeuchi in progress · notes/[31mredspec.md" "$(sl "$SID")"

  marker "$d/home/specs/plan.md"
  assert_eq "a path under \$HOME is shown with ~" "kabeuchi in progress · ~/specs/plan.md" "$(sl "$SID")"
  marker "$d/home"
  assert_eq "\$HOME itself is shown as ~" "kabeuchi in progress · ~" "$(sl "$SID")"
  marker "$d/homework/plan.md"
  assert_eq "a sibling sharing \$HOME's prefix is left alone" "kabeuchi in progress · $d/homework/plan.md" "$(sl "$SID")"
  marker "docs/plan.md"
  assert_eq "a relative path is shown as it is" "kabeuchi in progress · docs/plan.md" "$(sl "$SID")"

  # printf %s, never %b: a backslash sequence is printed as it is, and a \c
  # does not cut the line short.
  marker 'docs/\e[31mred\c-tail.md'
  assert_eq "backslash sequences are printed literally, line not cut short" \
    'kabeuchi in progress · docs/\e[31mred\c-tail.md' "$(sl "$SID")"

  # C1 controls (U+0080-U+009F, two bytes in UTF-8) are stripped too: a
  # terminal may take U+009B as CSI and U+009D as OSC. Other non-ASCII text
  # is kept, and a C1 that only forms once another one is removed is caught.
  marker "notes/a$(printf '\302\233')31mb$(printf '\302\235')c$(printf '\302\234')d$(printf '\302\302\233\233')e-é-あ.md"
  assert_eq "C1 controls are stripped, other non-ASCII kept" "kabeuchi in progress · notes/a31mbcde-é-あ.md" "$(sl "$SID")"

  # Out-of-range or unanchored URLs are plain text, never a link.
  o39="$(printf 'o%.0s' $(seq 39))"; r100="$(printf 'r%.0s' $(seq 100))"
  marker "$GH/$o39/$r100/issues/123456789012345678"
  assert_eq "a 39-character owner, 100-character repo and 18-digit number link" \
    "$(link "$o39/$r100#123456789012345678" "$GH/$o39/$r100/issues/123456789012345678")" "$(sl "$SID")"
  for t in "$GH/${o39}o/r/issues/9" "$GH/o/${r100}r/issues/9" "$GH/o/r/issues/1234567890123456789" \
           "x$GH/o/r/issues/9" " $GH/o/r/issues/9"; do
    marker "$t"
    assert_eq "plain text: ${t:0:60}" "kabeuchi in progress · $t" "$(sl "$SID")"
  done

  # Only the first 4096 bytes of the marker are read, so a huge first line
  # cannot stall the status line; and a symlink is not followed.
  marker "docs/$(printf 'x%.0s' $(seq 9000)).md"
  out="$(sl "$SID")"
  assert_eq "a long first line is cut at 4096 bytes" "kabeuchi in progress · docs/$(printf 'x%.0s' $(seq 4091))" "$out"
  printf 'secret first line\n' > "$d/elsewhere"
  rm -f "$KABEUCHI_DIR/$SID"; ln -s "$d/elsewhere" "$KABEUCHI_DIR/$SID"
  rc=0; out="$(sl "$SID")" || rc=$?
  assert_eq "a symlinked marker is not followed, exits 0" "0:" "$rc:$out"
  rm -f "$KABEUCHI_DIR/$SID"

  # The placeholder mark.sh seeds before the target is resolved, with the pid
  # line mark.sh writes below it: shown as plain text, the pid line ignored.
  rm -f "$KABEUCHI_DIR/$SID"
  CLAUDE_PID=$$ bash "$MARK" set "$SID" "" </dev/null >/dev/null 2>&1
  assert_eq "mark.sh wrote the pid line under the placeholder" "pid=$$" "$(sed -n 2p "$KABEUCHI_DIR/$SID")"
  assert_eq "the placeholder is plain text and the pid line is ignored" \
    "kabeuchi in progress · (resolving target)" "$(sl "$SID")"

  # Another session's marker must not leak into this one.
  assert_eq "another session's marker does not leak in" "" "$(sl "aaaaaaaa-0000-0000-0000-000000000000")"

  # An invalid session id prints nothing and exits 0 — even one that would
  # name an existing file outside the marker directory.
  printf 'https://github.com/o/r/issues/1\n' > "$d/outside"
  mkdir -p "$KABEUCHI_DIR/sub"
  printf 'https://github.com/o/r/issues/1\n' > "$KABEUCHI_DIR/sub/x"
  for sid in "" "." ".." "../outside" "sub/x" "a b"; do
    rc=0; out="$(sl "$sid")" || rc=$?
    assert_eq "invalid session_id [${sid}] prints nothing" "" "$out"
    assert_eq "invalid session_id [${sid}] exits 0" "0" "$rc"
  done

  # The status line must never break: every payload exits 0, quietly.
  for payload in "{}" "not json at all" "" '{"session_id":'; do
    rc=0; out="$(printf '%s' "$payload" | bash "$STATUSLINE" 2>&1)" || rc=$?
    assert_eq "exits 0 and prints nothing for payload: ${payload:-(empty)}" "0:" "$rc:$out"
  done
  # A marker that is a directory, or empty, prints nothing.
  rm -f "$KABEUCHI_DIR/$SID"; mkdir "$KABEUCHI_DIR/$SID"
  rc=0; out="$(sl "$SID")" || rc=$?
  assert_eq "a directory where the marker should be prints nothing, exits 0" "0:" "$rc:$out"
  rmdir "$KABEUCHI_DIR/$SID"; : > "$KABEUCHI_DIR/$SID"
  rc=0; out="$(sl "$SID")" || rc=$?
  assert_eq "an empty marker prints nothing, exits 0" "0:" "$rc:$out"
  # With neither KABEUCHI_DIR nor HOME set there is no marker directory to
  # look in: still nothing, and still exit 0 (set -u must not trip).
  rc=0; out="$(printf '{"session_id":"%s"}' "$SID" | env -u KABEUCHI_DIR -u HOME bash "$STATUSLINE" 2>&1)" || rc=$?
  assert_eq "no KABEUCHI_DIR and no HOME prints nothing, exits 0" "0:" "$rc:$out"

  # The README's combined example works as written, with its paths filled in:
  # one row per script that prints something, even when the user's own script
  # ends without a newline. The repository README is not shipped with the
  # skill, so in an installed copy this part is skipped.
  README="${HERE}/../../../README.md"
  if [ -f "$README" ]; then
    readme_kabeuchi="$(awk '/^## /{ f = ($0 == "## kabeuchi") } f' "$README")"
    printf '#!/usr/bin/env bash\ncat > /dev/null\nprintf "my line"\n' > "$d/my-statusline.sh"
    printf '#!/usr/bin/env bash\ncat > /dev/null\nprintf "jikkyo #27"\n' > "$d/jikkyo-statusline.sh"
    printf '#!/usr/bin/env bash\ncat > /dev/null\n' > "$d/jikkyo-silent.sh"
    chmod +x "$d/my-statusline.sh" "$d/jikkyo-statusline.sh" "$d/jikkyo-silent.sh"
    # wrapper <jikkyo stub>: the example, extracted and filled in.
    wrapper() {
      printf '%s\n' "$readme_kabeuchi" | sed -n '/^  #!\/usr\/bin\/env bash$/,/^  done$/p' | sed -e 's/^  //' \
        -e "s|~/.claude/my-statusline.sh|$d/my-statusline.sh|" \
        -e "s|/absolute/path/to/jikkyo/scripts/statusline.sh|$1|" \
        -e "s|/absolute/path/to/kabeuchi/scripts/statusline.sh|$STATUSLINE|" > "$d/wrapper.sh"
    }
    marker "$GH/gipcompany/skills/issues/52"
    wrapper "$d/jikkyo-statusline.sh"
    rc=0; out="$(printf '{"session_id":"%s"}' "$SID" | HOME="$d/home" bash "$d/wrapper.sh")" || rc=$?
    assert_eq "README.md: the combined example prints one row per script" \
      "0:my line"$'\n'"jikkyo #27"$'\n'"$(link "gipcompany/skills#52" "$GH/gipcompany/skills/issues/52")" "$rc:$out"
    rm -f "$KABEUCHI_DIR/$SID"
    wrapper "$d/jikkyo-silent.sh"
    rc=0; out="$(printf '{"session_id":"%s"}' "$SID" | HOME="$d/home" bash "$d/wrapper.sh")" || rc=$?
    assert_eq "README.md: ...skips the rows that are empty, and exits 0" "0:my line" "$rc:$out"
    unset -f wrapper
  else
    skip "README.md: no repository README next to this copy of the skill"
  fi

  unset KABEUCHI_DIR
  unset -f sl marker link
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

echo "tally.sh"
{
  # tally <line>... — feed one vote per argument, print both output lines.
  tally() { printf '%s\n' "$@" | bash "$TALLY"; }
  T=$'\t'

  out="$(tally "spec${T}A${T}valid" "code${T}A${T}valid" "docs${T}A${T}valid")"
  assert_eq "3 valid votes for one option -> unanimous" \
    "$(printf 'recommend\tA\n🗳️ 3/3 valid, unanimous')" "$out"

  out="$(tally "spec${T}A${T}valid" "code${T}A${T}valid" "docs${T}B${T}invalid")"
  assert_eq "an invalid vote stays in the denominator and is named" \
    "$(printf 'recommend\tA\n🗳️ 2/3 valid, unanimous (docs: invalid, evidence did not hold)')" "$out"

  out="$(tally "spec${T}A${T}valid" "code${T}A${T}valid" "docs${T}-${T}abstain")"
  assert_eq "an abstention leaves the denominator and is told apart from invalid" \
    "$(printf 'recommend\tA\n🗳️ 2/2 valid, unanimous (docs: abstained)')" "$out"

  out="$(tally "spec${T}A${T}valid" "code${T}-${T}failed" "docs${T}A${T}valid")"
  assert_eq "a failed voter leaves the denominator and is told apart from abstain" \
    "$(printf 'recommend\tA\n🗳️ 2/2 valid, unanimous (code: failed)')" "$out"

  out="$(tally "spec${T}A${T}valid" "code${T}B${T}valid" "docs${T}A${T}valid")"
  assert_eq "2 of 3 valid votes -> majority, the dissent is named" \
    "$(printf 'recommend\tA\n🗳️ 2/3 valid, majority (code: chose B instead)')" "$out"

  out="$(tally "spec${T}A${T}valid" "code${T}B${T}valid" "docs${T}C${T}valid")"
  assert_eq "a three-way split recommends nothing" \
    "$(printf 'recommend\t-\n🗳️ no recommendation, valid votes split (spec: A; code: B; docs: C)')" "$out"

  # The 2-vote threshold does not drop when others abstain or fail: one valid
  # vote is not a recommendation, however unopposed.
  out="$(tally "spec${T}A${T}valid" "code${T}-${T}abstain" "docs${T}-${T}failed")"
  assert_eq "a lone valid vote does not win" \
    "$(printf 'recommend\t-\n🗳️ no recommendation, only 1 valid vote (spec: A; code: abstained; docs: failed)')" "$out"

  # Two votes that agree but whose evidence did not hold must not win.
  out="$(tally "spec${T}A${T}invalid" "code${T}A${T}invalid" "docs${T}B${T}valid")"
  assert_eq "agreeing invalid votes do not outvote" "recommend	-" "$(printf '%s' "$out" | head -n 1)"

  out="$(tally "spec${T}A${T}invalid" "code${T}-${T}abstain" "docs${T}B${T}invalid")"
  assert_eq "no valid votes recommends nothing" \
    "$(printf 'recommend\t-\n🗳️ no recommendation, no valid votes (spec: invalid, evidence did not hold; code: abstained; docs: invalid, evidence did not hold)')" "$out"

  # A majority whose evidence was never checked must not pass as vetted.
  out="$(tally "spec${T}A${T}unverified" "code${T}A${T}unverified" "docs${T}A${T}unverified")"
  assert_eq "a verifier failure recommends nothing, even when all agree" \
    "$(printf 'recommend\t-\n🗳️ no recommendation, unverified because the verifier failed (spec: A (unverified); code: A (unverified); docs: A (unverified))')" "$out"

  d="$(mktemp -d)"
  printf 'spec\tA\tvalid\ncode\tA\tvalid\ndocs\tA\tvalid\n' > "$d/votes.tsv"
  out="$(bash "$TALLY" "$d/votes.tsv")"
  rm -rf "$d"
  assert_eq "votes can be read from a file" \
    "$(printf 'recommend\tA\n🗳️ 3/3 valid, unanimous')" "$out"

  # Malformed input is refused with exit 2 and nothing on stdout, so a caller
  # cannot mistake half a tally for a result.
  check_rejects() {
    local label="$1"; shift
    local rc=0 o
    o="$(printf '%s\n' "$@" | bash "$TALLY" 2>/dev/null)" || rc=$?
    if [ "$rc" -eq 2 ] && [ -z "$o" ]; then ok "$label"; else bad "$label (rc=$rc, stdout=[$o])"; fi
  }
  check_rejects "two votes instead of three exits 2" "spec${T}A${T}valid" "code${T}A${T}valid"
  check_rejects "four votes instead of three exits 2" "a${T}A${T}valid" "b${T}A${T}valid" "c${T}A${T}valid" "d${T}A${T}valid"
  check_rejects "an unknown state exits 2" "spec${T}A${T}valid" "code${T}A${T}maybe" "docs${T}A${T}valid"
  check_rejects "a missing field exits 2" "spec${T}A" "code${T}A${T}valid" "docs${T}A${T}valid"
  check_rejects "an extra field exits 2" "spec${T}A${T}valid${T}x" "code${T}A${T}valid" "docs${T}A${T}valid"
  check_rejects "abstain with an option id exits 2" "spec${T}A${T}abstain" "code${T}A${T}valid" "docs${T}A${T}valid"
  check_rejects "valid without an option id exits 2" "spec${T}-${T}valid" "code${T}A${T}valid" "docs${T}A${T}valid"
  check_rejects "an option id outside [A-Za-z0-9_-] exits 2" "spec${T}A;rm${T}valid" "code${T}A${T}valid" "docs${T}A${T}valid"
  check_rejects "unverified mixed with valid exits 2" "spec${T}A${T}unverified" "code${T}A${T}valid" "docs${T}A${T}valid"
  check_rejects "a control character in the perspective exits 2" $'sp\033ec'"${T}A${T}valid" "code${T}A${T}valid" "docs${T}A${T}valid"

  rc=0; bash "$TALLY" --lang </dev/null >/dev/null 2>&1 || rc=$?
  assert_eq "an unknown option exits 2" "2" "$rc"
  rc=0; bash "$TALLY" /no/such/file >/dev/null 2>&1 || rc=$?
  assert_eq "a missing input file exits 2" "2" "$rc"
}

echo "grilled-line.sh"
# The backticks below are literal markdown, never command substitution.
# shellcheck disable=SC2016
{
  TS='2026-11-15T17:41:59+09:00'
  OLD='> Grilled with `/kabeuchi` at 2026-11-14T09:00:00+09:00 — ready for `/goal`.'
  NEW_READY="> Grilled with \`/kabeuchi\` at ${TS} — ready for \`/goal\`."
  NEW_GAPS="> Grilled with \`/kabeuchi\` at ${TS} — not yet ready for \`/goal\`; see Known gaps."
  # gl <key> <body>: run the script on <body> with the fixed timestamp.
  gl() { printf '%s' "$2" | bash "$GRILLED" "$TS" "$1"; }

  out="$(gl ready "$(printf 'Spec\n\nBody text')")"
  assert_eq "no existing line: one blank line and the line are appended" \
    "$(printf 'Spec\n\nBody text\n\n%s' "$NEW_READY")" "$out"

  out="$(gl ready "")"
  assert_eq "an empty body becomes the line alone" "$NEW_READY" "$out"

  out="$(gl ready "$(printf 'Spec\n\n%s\n' "$OLD")")"
  assert_eq "a line at the end is replaced" "$(printf 'Spec\n\n%s' "$NEW_READY")" "$out"

  out="$(gl ready "$(printf 'Spec\n\n%s\n\nMore text\n' "$OLD")")"
  assert_eq "a line moved up the body is removed with its blank line, the new one goes last" \
    "$(printf 'Spec\n\nMore text\n\n%s' "$NEW_READY")" "$out"

  out="$(gl ready "$(printf 'Spec\n\n%s\nMore text\n' "$OLD")")"
  assert_eq "a line with content right after it leaves one blank line, so paragraphs stay apart" \
    "$(printf 'Spec\n\nMore text\n\n%s' "$NEW_READY")" "$out"

  out="$(gl ready "$(printf '%s\n\nSpec\n' "$OLD")")"
  assert_eq "a line at the very top is removed with the blank line after it" \
    "$(printf 'Spec\n\n%s' "$NEW_READY")" "$out"

  fenced_bt="$(printf 'Spec\n\n```markdown\n%s\n```\n' "$OLD")"
  out="$(gl ready "$fenced_bt")"
  assert_eq "a line inside a \`\`\` fence is left untouched" \
    "$(printf '%s\n\n%s' "$fenced_bt" "$NEW_READY")" "$out"

  fenced_tl="$(printf 'Spec\n\n~~~~\n%s\n~~~\n%s\n~~~~\n' "$OLD" "$OLD")"
  out="$(gl ready "$fenced_tl")"
  assert_eq "a line inside a ~~~ fence is left untouched (a shorter fence does not close it)" \
    "$(printf '%s\n\n%s' "$fenced_tl" "$NEW_READY")" "$out"

  fenced_in="$(printf 'Spec\n\n   ```\n%s\n   ```\n' "$OLD")"
  out="$(gl ready "$fenced_in")"
  assert_eq "a line inside a fence indented by three spaces is left untouched" \
    "$(printf '%s\n\n%s' "$fenced_in" "$NEW_READY")" "$out"

  # Four spaces make an indented code block, not a fence (CommonMark, GitHub),
  # so a line after it is a real grilled line and is replaced.
  code_block="$(printf 'Spec\n\n    ```\n    x\n\n%s\n\nMore\n' "$OLD")"
  out="$(gl ready "$code_block")"
  assert_eq "a \`\`\` indented by four spaces opens no fence" \
    "$(printf 'Spec\n\n    ```\n    x\n\nMore\n\n%s' "$NEW_READY")" "$out"

  # A fence still open at the end runs to the end, so a line in it is content;
  # the script closes it before the new line, so the new line is not inside it
  # and a later run finds and replaces it instead of adding another.
  unclosed="$(printf 'Spec\n\n```\n%s\n' "$OLD")"
  out="$(gl ready "$unclosed")"
  assert_eq "an unclosed fence is closed before the new line" \
    "$(printf '%s\n```\n\n%s' "$unclosed" "$NEW_READY")" "$out"
  again="$(gl ready "$out")"
  assert_eq "after an unclosed fence, a second run still leaves one line" "$out" "$again"
  out="$(gl ready "$(printf 'Spec\n\n~~~~\ncode\n')")"
  assert_eq "an unclosed fence is closed with its own character and length" \
    "$(printf 'Spec\n\n~~~~\ncode\n~~~~\n\n%s' "$NEW_READY")" "$out"

  after_fence="$(printf 'Spec\n\n```\ncode\n```\n\n%s\n' "$OLD")"
  out="$(gl ready "$after_fence")"
  assert_eq "a line after a closed fence is replaced" \
    "$(printf 'Spec\n\n```\ncode\n```\n\n%s' "$NEW_READY")" "$out"

  lookalikes="$(printf 'Spec\n\n  %s\n> %s\n%s Thanks.\n> Grilled with `/kabeuchi` at 2026-11-14 — ready for `/goal`.' "$OLD" "$OLD" "$OLD")"
  out="$(gl ready "$lookalikes")"
  assert_eq "indented, quoted, extended and malformed copies are content" \
    "$(printf '%s\n\n%s' "$lookalikes" "$NEW_READY")" "$out"

  gaps="$(printf 'Spec\n\n## Known gaps\n\n- **Scope** — nothing states what is out of scope.\n\n%s\n' "$OLD")"
  out="$(gl gaps "$gaps")"
  assert_eq "with \"Known gaps\" present the line goes below it" \
    "$(printf 'Spec\n\n## Known gaps\n\n- **Scope** — nothing states what is out of scope.\n\n%s' "$NEW_GAPS")" "$out"

  two="$(printf 'Spec\n\n%s\n\nMore\n\n%s' "$OLD" "$OLD")"
  out="$(gl ready "$two")"
  assert_eq "every existing line is removed, so at most one remains" \
    "$(printf 'Spec\n\nMore\n\n%s' "$NEW_READY")" "$out"

  once="$(gl gaps "$gaps")"
  twice="$(gl gaps "$once")"
  assert_eq "running it twice gives the same body" "$once" "$twice"

  out="$(printf 'Spec\r\n\r\n%s\r\n\r\n\r\n' "$OLD" | bash "$GRILLED" "$TS" ready)"
  assert_eq "the body is normalized (CRLF, trailing blank lines)" \
    "$(printf 'Spec\n\n%s' "$NEW_READY")" "$out"

  for key in ready gaps not-ready not-checked; do
    out="$(gl "$key" "$(printf 'Spec\n\n%s' "$OLD")")"
    last="$(printf '%s' "$out" | tail -n 1)"
    count="$(printf '%s\n' "$out" | grep -c '^> Grilled with')"
    assert_eq "key ${key}: exactly one line, and it is last" "1" "$count"
    case "$last" in "> Grilled with \`/kabeuchi\` at ${TS} — "*) ok "key ${key}: the line has the prefix and timestamp" ;;
      *) bad "key ${key}: the line has the prefix and timestamp ([$last])" ;; esac
    # Its own output counts as a grilled line, so every key's line is replaced.
    again="$(gl ready "$out")"
    assert_eq "key ${key}: its line is recognised and replaced" "$(printf 'Spec\n\n%s' "$NEW_READY")" "$again"
  done

  # Bad usage exits 2 with nothing on stdout, like tally.sh and merge3.sh.
  check_usage() {
    local label="$1"; shift
    local rc=0 o
    o="$(printf 'Spec' | bash "$GRILLED" "$@" 2>/dev/null)" || rc=$?
    if [ "$rc" -eq 2 ] && [ -z "$o" ]; then ok "$label"; else bad "$label (rc=$rc, stdout=[$o])"; fi
  }
  check_usage "an unknown tail key exits 2" "$TS" ready-for-goal
  check_usage "a timestamp in Z form exits 2" "2026-11-15T08:41:59Z" ready
  check_usage "a timestamp without seconds exits 2" "2026-11-15T17:41+09:00" ready
  check_usage "a date alone exits 2" "2026-11-15" ready
  check_usage "a timestamp with trailing text exits 2" "${TS}x" ready
  check_usage "no arguments exits 2"
  check_usage "a missing tail key exits 2" "$TS"
  check_usage "an extra argument exits 2" "$TS" ready extra
}

echo "grilled line wording (SKILL.md, references, README)"
# The backticks below are literal markdown, never command substitution.
# shellcheck disable=SC2016
{
  # The grilled line is found again by its fixed prefix, so every example of it
  # in the docs must use that exact prefix and one of the four tails. (The
  # prefix holds no ERE metacharacters, so it is used as-is in the regex.)
  REF="${HERE}/../references/ready-for-goal.md"
  README="${HERE}/../../../README.md"
  prefix='> Grilled with `/kabeuchi` at '
  date_re='[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2}'
  tails='ready for `/goal`\.|not yet ready for `/goal`; see Known gaps\.|not yet ready for `/goal`\.|not checked for `/goal`\.'
  for tail in 'ready for `/goal`.' 'not yet ready for `/goal`; see Known gaps.' 'not yet ready for `/goal`.' 'not checked for `/goal`.'; do
    if grep -qxF "${prefix}2026-11-15T17:41:59+09:00 — ${tail}" "$REF"; then
      ok "ready-for-goal.md shows the line ending \"${tail}\""
    else
      bad "ready-for-goal.md shows the line ending \"${tail}\""
    fi
  done
  # grilled-line.sh spells out the four tails in code; the docs' examples must
  # be exactly the four lines it writes, no more and no fewer.
  script_lines="$(for key in ready gaps not-ready not-checked; do
    bash "$GRILLED" 2026-11-15T17:41:59+09:00 "$key" </dev/null; echo; done | sort)"
  doc_lines="$(grep -xE "${prefix}2026-11-15T17:41:59\+09:00 — .*" "$REF" | sort -u)"
  assert_eq "ready-for-goal.md's example lines are the four lines grilled-line.sh writes" \
    "$script_lines" "$doc_lines"
  for key in ready gaps not-ready not-checked; do
    line="$(bash "$GRILLED" 2026-11-15T17:41:59+09:00 "$key" </dev/null)"
    if printf '%s\n' "$line" | grep -qxE "${prefix}${date_re} — (${tails})"; then
      ok "grilled-line.sh's ${key} line matches the docs' pattern"
    else
      bad "grilled-line.sh's ${key} line matches the docs' pattern ([$line])"
    fi
  done
  # ready-for-goal.md spells out the pattern a line must match whole, outside
  # code fences, to count as a grilled line; it must be this same pattern.
  if grep -qxF "    ^${prefix}${date_re} — (${tails})\$" "$REF"; then
    ok "ready-for-goal.md states the exact grilled line pattern"
  else
    bad "ready-for-goal.md states the exact grilled line pattern"
  fi
  # grilled_lines <file>: every line that looks like an example of the grilled
  # line, indentation removed. The pattern is loose on purpose (any spaces
  # before and after ">"), so a malformed example is collected and then fails
  # the exact match below instead of slipping past it.
  grilled_lines() { grep -E '^ *> *Grilled' "$1" | grep -vF '<timestamp>' | sed 's/^ *//'; }
  # stray_lines <file>: the collected lines that are not exact grilled lines.
  stray_lines() { grilled_lines "$1" | grep -vxE "${prefix}${date_re} — (${tails})"; }

  # The repository README is not shipped with the skill: in an installed copy
  # (say ~/.claude/skills/kabeuchi) it is not there, which says nothing about
  # the skill, so its part of the check is skipped, visibly, instead of failing.
  docs=("${HERE}/../SKILL.md" "$REF")
  if [ -f "$README" ]; then docs+=("$README")
  else skip "README.md: no repository README next to this copy of the skill"; fi
  for f in "${docs[@]}"; do
    name="${f##*/}"
    if [ -z "$(grilled_lines "$f")" ]; then bad "${name} shows the grilled line"; continue; fi
    assert_eq "${name}: every grilled line uses the fixed prefix and a known tail" "" "$(stray_lines "$f")"
  done

  # The collector catches malformed examples: no space or two spaces after ">".
  d="$(mktemp -d)"
  for bad_line in '>Grilled with `/kabeuchi` at 2026-11-15T17:41:59+09:00 — ready for `/goal`.' \
                  '>  Grilled with `/kabeuchi` at 2026-11-15T17:41:59+09:00 — ready for `/goal`.' \
                  '  >Grilled with `/kabeuchi` at 2026-11-15T17:41:59+09:00 — ready for `/goal`.'; do
    printf 'Doc\n\n%s\n' "$bad_line" > "$d/doc.md"
    if [ -n "$(stray_lines "$d/doc.md")" ]; then ok "the wording test catches [${bad_line:0:16}…]"
    else bad "the wording test catches [${bad_line:0:16}…]"; fi
  done
  rm -rf "$d"
}

echo "agents/kabeuchi-voter.md"
{
  # The preflight stops every session whose installed kabeuchi-voter lacks one
  # of these phrases in its description, so the shipped description must
  # contain each of them, or rewording it makes every /kabeuchi stop at startup.
  # The phrases are read from both places that list them: the bold phrases in
  # SKILL.md's preflight sentence (from "description lacks" to "it is an older
  # copy"), which is what a session actually checks, and the gotchas table's
  # "description lacks" rows. The two sets must be equal, so a phrase added to
  # either one alone fails here instead of going unchecked.
  SKILL_MD="${HERE}/../SKILL.md"
  GOTCHAS="${HERE}/../references/gotchas.md"
  VOTER="${HERE}/../agents/kabeuchi-voter.md"

  # desc_has <agent file> <phrase>: exit 0 if the frontmatter's description:
  # line contains the phrase as a fixed string. It reads that one line only, so
  # the description must stay on a single line (no YAML folded or block style).
  desc_has() {
    awk 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit }
         /^description:/ { print }' "$1" | grep -qF -- "$2"
  }

  # One phrase per line, sorted. Lines are joined first, so a phrase wrapped
  # across two lines of SKILL.md is still read as one.
  skill_phrases="$(awk '/description lacks/ { on = 1 } on { print } /it is an older copy/ { exit }' "$SKILL_MD" |
    tr '\n' ' ' | grep -o '\*\*"[^"]*"\*\*' | sed 's/^\*\*"//; s/"\*\*$//' | sort)"
  gotchas_phrases="$(grep -o 'description lacks "[^"]*"' "$GOTCHAS" |
    sed 's/^description lacks "//; s/"$//' | sort)"

  if [ -n "$skill_phrases" ]; then ok "the preflight in SKILL.md names at least one phrase"
  else bad "no bold phrase found in SKILL.md's preflight sentence"; fi
  assert_eq "SKILL.md's preflight and the gotchas table name the same phrases" \
    "$skill_phrases" "$gotchas_phrases"

  while IFS= read -r p; do
    [ -n "$p" ] || continue
    if desc_has "$VOTER" "$p"; then ok "the voter's description contains \"$p\""
    else bad "the voter's description lacks \"$p\" (the preflight would stop every session)"; fi
  done <<<"$skill_phrases"

  # The check fails on a description that lacks a phrase, including one where
  # the phrase appears only in the body, outside the description: line.
  d="$(mktemp -d)"
  printf -- '---\nname: kabeuchi-voter\ndescription: Read-only voter. Reads the per-question brief.\n---\n\nready to hand to /goal\n' >"$d/voter.md"
  rc=0; desc_has "$d/voter.md" "ready to hand to /goal" || rc=$?
  assert_eq "a description lacking a phrase fails the check" "1" "$rc"
  rc=0; desc_has "$d/voter.md" "Reads the per-question brief" || rc=$?
  assert_eq "a description containing a phrase passes the check" "0" "$rc"
  rm -rf "$d"
}

echo "done criteria marker wording (SKILL.md, references)"
# The backticks below are literal markdown, never command substitution.
# shellcheck disable=SC2016
{
  # Phase 2 writes done criteria as task-list items, falling back to `* [ ]`,
  # and the ready-for-goal checker's Done criteria row must accept that marker
  # as well as `- [ ]`. If the two drift apart, the checker reports every
  # session's own done criteria as a gap.
  SKILL_MD="${HERE}/../SKILL.md"
  REF="${HERE}/../references/ready-for-goal.md"

  # done_row <file>: the checklist row whose first cell is **Done criteria**.
  done_row() { grep -F -- '| **Done criteria** |' "$1"; }
  # phase2_rule <file>: the task-list rule paragraph inside Phase 2 only.
  phase2_rule() {
    awk '/^## Phase 2:/ { on = 1; next } /^## / { on = 0 } on' "$1" |
      grep -F -- '**Done criteria are written as task-list items.**'
  }
  # row_ok <file>: exit 0 if the Done criteria row names both markers.
  row_ok() {
    local row; row="$(done_row "$1")" || return 1
    printf '%s' "$row" | grep -qF -- '`* [ ]`' && printf '%s' "$row" | grep -qF -- '`- [ ]`'
  }
  # rule_ok <file>: exit 0 if Phase 2's rule names `* [ ]` as the fallback.
  rule_ok() { phase2_rule "$1" | grep -qF -- 'otherwise `* [ ]`'; }

  if row_ok "$REF"; then ok "the Done criteria row names both \`* [ ]\` and \`- [ ]\`"
  else bad "the Done criteria row in ready-for-goal.md does not name both \`* [ ]\` and \`- [ ]\`"; fi
  if rule_ok "$SKILL_MD"; then ok "SKILL.md Phase 2 names \`* [ ]\` as the fallback marker"
  else bad "SKILL.md Phase 2 does not name \`* [ ]\` as the fallback task-list marker"; fi

  # The checks fail when either side drifts.
  d="$(mktemp -d)"
  printf '| **Done criteria** | a task list (`- [ ]`) that can be ticked. |\n' >"$d/ref.md"
  rc=0; row_ok "$d/ref.md" || rc=$?
  assert_eq "a Done criteria row naming only \`- [ ]\` fails the check" "1" "$rc"
  printf '## Phase 1: x\n\n**Done criteria are written as task-list items.** otherwise `* [ ]`.\n\n## Phase 2: y\n\nnothing here\n' >"$d/skill.md"
  rc=0; rule_ok "$d/skill.md" || rc=$?
  assert_eq "a fallback rule outside Phase 2 fails the check" "1" "$rc"
  printf '## Phase 2: y\n\n**Done criteria are written as task-list items.** otherwise `- [ ]`.\n\n## Phase 3: z\n' >"$d/skill.md"
  rc=0; rule_ok "$d/skill.md" || rc=$?
  assert_eq "a Phase 2 rule without the \`* [ ]\` fallback fails the check" "1" "$rc"
  rm -rf "$d"
}

echo
printf 'total: %d passed, %d failed, %d skipped\n' "$pass" "$fail" "$skipped"
[ "$fail" -eq 0 ]
