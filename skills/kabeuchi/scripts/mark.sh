#!/usr/bin/env bash
#
# mark.sh — place or remove the "kabeuchi in progress" marker for one session.
#
# kabeuchi-mark-sh
#
# ^ DO NOT REMOVE OR RENAME that marker, and see prompt-hook.sh for the same one
# on that script. A `SessionEnd` hook — the one that clears a marker for a
# session Claude never got to finish — has to find this file by path, and a path
# is not an identity: it searches a plugin root, a project's .claude/skills and
# a personal ~/.claude/skills in turn, and `$CLAUDE_PLUGIN_ROOT` /
# `$CLAUDE_PROJECT_DIR` are whatever the environment says they are at the moment
# the session ends. Grepping for this marker is what stops the hook running some
# other project's `scripts/mark.sh`, which matters more here than for the prompt
# hook: this one is invoked to DELETE something. tests/run.sh asserts it is here.
#
# The hook lives in the user's settings.json rather than this skill's
# frontmatter, because a `SessionEnd` hook declared by a skill never fires.
#
# Usage:
#   mark.sh set   [session_id] [target]   # no target arg -> read it from stdin
#   mark.sh clear [session_id]
#   mark.sh path  [session_id]            # print the marker path, for debugging
#
# The marker is a one-line file at $KABEUCHI_DIR/<session_id> (default
# ~/.claude/kabeuchi/<session_id>) holding the grilling target — a GitHub issue
# URL or a local markdown path. Two readers consume it, and neither needs Claude
# to remember anything:
#
#   - the status line, which grows a second row for as long as the file exists;
#   - scripts/prompt-hook.sh, the UserPromptSubmit hook registered by SKILL.md,
#     which re-states the target and the kabeuchi contract on every turn.
#
# Marking per session is what makes a leftover file harmless: a new session gets
# a new id, so a marker that outlives its session can never light up someone
# else's status line.
#
# The file's first line is the target and is all any reader needs. A second line
# records the owning Claude process (`pid=<n>`) when it is known, which is how a
# marker gets collected after a session that never cleared it — a closed
# terminal, a crash, a `kill -9`. The next `set` drops every marker whose owner
# is gone, with an age sweep as the backstop for markers that carry no pid.
#
# THIS SCRIPT MUST NEVER FAIL. It runs from an injected command in SKILL.md, and
# a non-zero exit there aborts the whole /kabeuchi invocation — losing the skill
# for the sake of a decoration. Every path therefore ends in `exit 0`, and
# success prints nothing so the injected text stays empty.
#
# SKILL.md's injected `set` passes NO target at all — only a literal placeholder
# — and Phase 1 refreshes the marker once the real target is resolved. That is
# deliberate: `$ARGUMENTS` is substituted as text into the command line before
# the shell sees it, so anything the user typed becomes shell syntax. A quote or
# a `;` breaks the command apart and fails the permission check, which aborts the
# invocation; and no quoting construct helps, because the construct's own
# terminator is part of the substituted text — a quoted heredoc ends early on a
# target containing its delimiter, and the rest of the argument runs as commands.
# Keeping the target off that command line is the only thing that closes the
# class, and it costs nothing here: the placeholder is on screen for a moment.
#
# `set` still accepts a target on stdin or as an argument. Phase 1 and the tests
# use it; the injected command does not.
#
# Exit codes:
#   0  always
#
set -u

MAX_TARGET_LEN=200      # keeps the status line from wrapping on a long path
STALE_DAYS=7            # sweep markers left behind by a session that was killed

die_quietly() { exit 0; }

marker_dir() { printf '%s' "${KABEUCHI_DIR:-$HOME/.claude/kabeuchi}"; }

# A session id becomes a filename, so refuse anything that could escape the
# directory or name a dotfile. Claude Code session ids are UUIDs; this only ever
# rejects a caller passing something else.
valid_session() {
  case "${1:-}" in
    "" | . | .. ) return 1 ;;
    *[!A-Za-z0-9._-]* ) return 1 ;;
    *) return 0 ;;
  esac
}

# Resolve the session id: explicit argument first, then the environment variable
# Claude Code exports to hooks and injected commands, then the hook JSON on
# stdin (SessionEnd delivers it there and sets no argument).
resolve_session() {
  local sid="${1:-}"
  [ -n "$sid" ] || sid="${CLAUDE_CODE_SESSION_ID:-}"
  [ -n "$sid" ] || sid="${CLAUDE_SESSION_ID:-}"
  if [ -z "$sid" ] && [ ! -t 0 ]; then
    sid="$(sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' 2>/dev/null | head -n 1)"
  fi
  printf '%s' "$sid"
}

# Collapse the target to one printable line: the status line is a single row and
# a control character in it would corrupt the whole bar.
sanitize_target() {
  local t="$1"
  t="${t%%$'\n'*}"
  t="$(printf '%s' "$t" | tr -d '\000-\037\177')"
  t="${t#"${t%%[![:space:]]*}"}"
  t="${t%"${t##*[![:space:]]}"}"
  printf '%.'"$MAX_TARGET_LEN"'s' "$t"
}

# The pid of the Claude process that owns a marker, when Claude Code told us.
owner_pid() {
  case "${CLAUDE_PID:-}" in
    "" | *[!0-9]* ) return ;;
    *) printf '%s' "$CLAUDE_PID" ;;
  esac
}

# THE SWEEP DELETES FILES, so it must be able to prove that a file is one of
# ours before touching it. The marker directory is caller-settable through
# KABEUCHI_DIR, and a sweep that trusted that variable would cheerfully delete
# whatever else lived there — point it at ~/.claude and a week-old settings.json
# is gone. A marker's name is a session id, and Claude Code session ids are
# UUIDs, so require that shape and skip everything else. `valid_session` is the
# wrong test here: it accepts `settings.json` too, because writing a file under a
# name is safe in ways that deleting one is not.
#
# A marker named outside that shape is therefore never collected. That is the
# direction to fail in: a stray file that lingers costs a directory entry, a
# stray file that is deleted costs someone their data.
session_shaped() {
  case "${1:-}" in
    *[!0-9A-Fa-f-]* ) return 1 ;;
    *-*-*-*-* ) return 0 ;;
    *) return 1 ;;
  esac
}

# Drop markers whose owning session is gone. This catches the cases a session-end
# hook cannot — a closed terminal, a crash, a kill -9 — because it asks the OS
# whether the process still exists rather than trusting anyone to clean up.
sweep_stale() {
  local dir="$1" f pid
  for f in "$dir"/*; do
    [ -f "$f" ] || continue
    session_shaped "${f##*/}" || continue
    pid="$(sed -n '2s/^pid=\([0-9][0-9]*\)$/\1/p' "$f" 2>/dev/null)"
    if [ -n "$pid" ]; then
      kill -0 "$pid" 2>/dev/null || rm -f "$f" 2>/dev/null
      continue
    fi
    # Backstop for markers written without an owner pid, scoped to this one file
    # so the age test can never reach a name we did not just approve.
    find "$f" -maxdepth 0 -type f -mtime "+${STALE_DAYS}" -delete 2>/dev/null || true
  done
}

action="${1:-}"
[ -n "$action" ] || die_quietly
shift 2>/dev/null || true

case "$action" in
  set)
    session="$(resolve_session "${1:-}")"
    valid_session "$session" || die_quietly
    target="${2:-}"
    if [ -z "$target" ] && [ ! -t 0 ]; then
      target="$(cat 2>/dev/null)"
    fi
    target="$(sanitize_target "$target")"
    # An unresolved target is still worth marking: "kabeuchi in progress" with a
    # placeholder beats no second row at all, and Phase 1 fills in the real name.
    [ -n "$target" ] || target="(resolving target)"

    dir="$(marker_dir)"
    mkdir -p "$dir" 2>/dev/null || die_quietly
    sweep_stale "$dir"
    tmp="$dir/.tmp.$$"
    pid="$(owner_pid)"
    if {
         printf '%s\n' "$target"
         [ -n "$pid" ] && printf 'pid=%s\n' "$pid"
         true
       } > "$tmp" 2>/dev/null; then
      mv -f "$tmp" "$dir/$session" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    else
      rm -f "$tmp" 2>/dev/null
    fi
    ;;

  clear)
    session="$(resolve_session "${1:-}")"
    valid_session "$session" || die_quietly
    rm -f "$(marker_dir)/$session" 2>/dev/null || true
    ;;

  path)
    session="$(resolve_session "${1:-}")"
    valid_session "$session" || die_quietly
    printf '%s\n' "$(marker_dir)/$session"
    ;;
esac

exit 0
