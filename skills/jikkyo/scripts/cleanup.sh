#!/usr/bin/env bash
#
# cleanup.sh — decide whether the worktree a jikkyo run used can be removed.
#
#   cleanup.sh <worktree path>
#
# Prints `remove` or `keep` on the first line and the reason on the second.
# It never removes anything itself; the parent session carries out what it
# prints. `remove` only when both hold:
#
#   - the worktree has no uncommitted changes (untracked files count), and
#   - its HEAD is on a remote-tracking branch: the branch was pushed, or it has
#     no commits beyond the base it was created from.
#
# Anything it cannot establish gives `keep`: jikkyo never deletes work silently.
#
# The child could have written git config in the worktree; `git status`
# would run a core.fsmonitor command from it, so that is turned off here.
#
set -uo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: cleanup.sh <worktree path>" >&2
  exit 2
fi
wt="$1"

decide() { printf '%s\n%s\n' "$1" "$2"; exit 0; }

[ -d "$wt" ] || decide keep "no worktree at $wt"
top="$(git -C "$wt" rev-parse --show-toplevel 2>/dev/null)" || decide keep "$wt is not a git worktree"
[ "$(cd "$wt" && pwd -P)" = "$(cd "$top" && pwd -P)" ] || decide keep "$wt is not the top of a worktree"

dirty="$(git -c core.fsmonitor=false -C "$wt" status --porcelain --untracked-files=all 2>/dev/null)" \
  || decide keep "git status failed in $wt"
[ -z "$dirty" ] || decide keep "uncommitted changes in $wt"

remote="$(git -C "$wt" branch -r --contains HEAD 2>/dev/null)" \
  || decide keep "could not read the remote-tracking branches"
[ -n "$remote" ] || decide keep "commits on $(git -C "$wt" rev-parse --abbrev-ref HEAD 2>/dev/null) are not pushed"

decide remove "no uncommitted changes, and HEAD is on $(printf '%s' "$remote" | head -n 1 | sed 's/^[ *]*//')"
