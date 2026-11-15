#!/usr/bin/env bash
#
# statusline.sh — show a running kabeuchi in the Claude Code status line.
#
#   {"statusLine": {"type": "command", "command": "<skill dir>/scripts/statusline.sh"}}
#
# It reads the status line's JSON on stdin, takes `session_id`, and if that
# session has a kabeuchi marker prints one line:
#
#   kabeuchi in progress · OWNER/REPO#N
#
# With no marker it prints nothing, so the row is there only while a grilling
# runs.
#
# The marker is the file ${KABEUCHI_DIR:-$HOME/.claude/kabeuchi}/<session_id>,
# written by mark.sh and read here the same way prompt-hook.sh reads it. Its
# first line is the target — a GitHub issue URL, a local markdown path, or the
# placeholder `(resolving target)` until the target is resolved — and that line
# is all this script uses; an optional second `pid=<n>` line is ignored.
#
# No jq: the session id is pulled out with the same sed extraction and
# A-Za-z0-9._- check as mark.sh and prompt-hook.sh, so there is one parsing
# path to test and kabeuchi needs nothing new installed.
#
# No refreshInterval is needed: the marker changes only when a grilling starts
# and ends, and the session is active the whole time in between, so the status
# line's event-driven updates keep it current.
#
# Exit codes:
#   0  always — whatever goes wrong, it prints nothing rather than break the
#      status line it is part of.
#
set -u

main() {
  local session marker target
  [ -t 0 ] && return 0
  session="$(head -c 1048576 | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
  case "$session" in
    "" | . | .. | *[!A-Za-z0-9._-]* ) return 0 ;;
  esac

  marker="${KABEUCHI_DIR:-$HOME/.claude/kabeuchi}/$session"
  [ -f "$marker" ] && [ -s "$marker" ] || return 0
  target="$(head -n 1 "$marker")"
  [ -n "$target" ] || return 0

  printf '%s\n' "kabeuchi in progress · $target"
  return 0
}

exec 2>/dev/null
main
exit 0
