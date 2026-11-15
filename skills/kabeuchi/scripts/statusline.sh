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

ESC=$'\e'
BEL=$'\a'

# A GitHub issue URL, parsed and validated by one anchored regex: the owner is a
# GitHub login (alphanumerics and single inner hyphens), the repository a run of
# A-Za-z0-9._- (`.` and `..` are rejected below), the number digits, and
# anything after it must start with `/`, `?` or `#`. Captures: 1 owner,
# 3 repository, 4 number.
ISSUE_RE='^https://github\.com/([A-Za-z0-9](-?[A-Za-z0-9])*)/([A-Za-z0-9._-]+)/issues/([0-9]+)([/?#].*)?$'

# issue_link <target>: print `OWNER/REPO#N` wrapped in an OSC 8 hyperlink to
# the issue, or fail when the target is not an issue URL this accepts. The link
# is rebuilt from the captures and never copied from the marker, so nothing the
# marker holds beyond those checked pieces reaches the escape sequence. It ends
# with BEL, the form every hyperlink example in the Claude Code status line
# docs uses.
issue_link() {
  local owner repo number url
  [[ "$1" =~ $ISSUE_RE ]] || return 1
  owner="${BASH_REMATCH[1]}"
  repo="${BASH_REMATCH[3]}"
  number="${BASH_REMATCH[4]}"
  [ "${#owner}" -le 39 ] && [ "${#repo}" -le 100 ] || return 1
  case "$repo" in . | ..) return 1 ;; esac
  number="${number#"${number%%[!0]*}"}"   # drop leading zeros
  [ -n "$number" ] && [ "${#number}" -le 18 ] || return 1
  url="https://github.com/$owner/$repo/issues/$number"
  printf '%s' "${ESC}]8;;${url}${BEL}${owner}/${repo}#${number}${ESC}]8;;${BEL}"
}

# fold_home <path>: the path with a leading $HOME shown as `~`, as a shell
# prompt does. Only a whole leading component is folded, so /Users/meow is left
# alone when $HOME is /Users/me.
fold_home() {
  local home="${HOME:-}"
  home="${home%/}"
  if [ -n "$home" ] && [ "$1" = "$home" ]; then
    printf '%s' "~"
  elif [ -n "$home" ] && [ "${1#"$home"/}" != "$1" ]; then
    printf '%s/%s' "~" "${1#"$home"/}"
  else
    printf '%s' "$1"
  fi
}

main() {
  local session dir marker target shown
  [ -t 0 ] && return 0
  session="$(head -c 1048576 | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)"
  case "$session" in
    "" | . | .. | *[!A-Za-z0-9._-]* ) return 0 ;;
  esac

  # With neither KABEUCHI_DIR nor HOME there is no marker directory: print
  # nothing rather than let set -u end the script with exit 1.
  dir="${KABEUCHI_DIR:-${HOME:+$HOME/.claude/kabeuchi}}"
  [ -n "$dir" ] || return 0
  marker="$dir/$session"
  [ -f "$marker" ] && [ -s "$marker" ] || return 0
  target="$(head -n 1 "$marker")"
  # mark.sh already strips control bytes, but anything that can write to the
  # marker directory can write a marker, and a stray ESC would let it draw on
  # the terminal. Strip them again before anything is printed.
  target="$(printf '%s' "$target" | LC_ALL=C tr -d '\000-\037\177')"
  [ -n "$target" ] || return 0

  # An issue URL becomes a link; anything else — a path, the placeholder, a URL
  # this does not accept — is plain text, with $HOME folded to `~`.
  shown="$(issue_link "$target")" || shown="$(fold_home "$target")"
  # Always %s, never %b: a backslash in a path is printed as it is.
  printf '%s\n' "kabeuchi in progress · $shown"
  return 0
}

exec 2>/dev/null
main
exit 0
