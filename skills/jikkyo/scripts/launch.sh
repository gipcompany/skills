#!/usr/bin/env bash
#
# launch.sh — start a headless `/goal` run on a GitHub issue and pipe its
# stream into report.sh, which live-reports the run on that issue.
#
#   launch.sh '<https://github.com/<owner>/<repo>/issues/<N>>'
#
# Run it as a background command from the repository the issue belongs to.
# Before the child starts it prints the worktree the child will use, so the
# parent session can clean it up at exit:
#
#   jikkyo: worktree name jikkyo-<N>-<timestamp>
#   jikkyo: worktree path <repo>/.claude/worktrees/jikkyo-<N>-<timestamp>
#   jikkyo: worktree branch worktree-jikkyo-<N>-<timestamp>
#
# Everything after that is report.sh's output. Exit status: 2 for a bad
# argument or a repository that does not match the issue, otherwise
# the pipeline's.
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The deny list the child runs under (see "What the deny list covers" in
# SKILL.md). Deny rules apply in every permission mode and nothing overrides
# them, but they match only the command as written: this stops the plain forms
# of operations the child never needs. It is not a sandbox.
DENY_RULES=(
  # Force pushes, including `+refspec` and the lease variants.
  'Bash(git push*--force*)'
  'Bash(git push -f*)'
  'Bash(git push * -f*)'
  'Bash(git push * +*)'
  # Deleting remote branches (and pushes that can delete them as a side effect).
  'Bash(git push*--delete*)'
  'Bash(git push -d*)'
  'Bash(git push * -d*)'
  'Bash(git push * :*)'
  'Bash(git push*--mirror*)'
  'Bash(git push*--prune*)'
  # Editing or deleting issue comments, so jikkyo's status comment stays its own.
  'Bash(gh issue comment*--edit-last*)'
  'Bash(gh issue comment*--delete-last*)'
  'Bash(gh api*issues/comments/*)'
  'Bash(gh api graphql*updateIssueComment*)'
  # Any DELETE through the API: comments, issues, and remote refs alike.
  'Bash(gh api*DELETE*)'
  # Closing or deleting issues. The PR's `Closes #N` is what closes the issue.
  'Bash(gh issue close*)'
  'Bash(gh issue delete*)'
  'Bash(gh api*state=closed*)'
  'Bash(gh api graphql*closeIssue*)'
  'Bash(gh api graphql*deleteIssue*)'
)

# The three instructions are appended to the goal condition after the URL, in
# the order todo, tick, log. They are constants, so nothing from the issue reaches the command line
# beyond the validated URL. They are also what the /goal evaluator judges
# against, which is why the todo one is worded as a way of working, not as a
# condition for the goal. Keep each on one line.
#
# report.sh computes progress and the remaining-time estimate from the child's
# TaskCreate / TaskUpdate events; a child left to itself often makes no todos.
# The log is what a later run resumes from (design: issue #27). It lives on the
# run's own branch, is pushed after every todo so a crash loses at most one
# step, and is deleted before the PR so it never reaches the base branch.
TODO_INSTRUCTION='Todos: before starting the work, break it into small steps with TaskCreate, one todo per step of a few minutes each, and mark each todo completed with TaskUpdate as soon as that step is done; add todos with TaskCreate when new steps come up. If the body of this issue has a task list (for example under "Acceptance criteria"), make one todo per task-list item, and tick the box of that item right after you mark its todo completed. Progress and the remaining time shown on the issue are computed from these todos.'
TICK_INSTRUCTION='Task-list boxes: as soon as a task-list item in the body of this issue (for example under "Acceptance criteria") is done and verified (tests run, output checked), tick that box on the issue, before you move on to the next item; do not save the ticks for one edit at the end. Tick only items you have verified, and never untick or reword anything. Change nothing in the body but "- [ ]" to "- [x]" on those lines: fetch the current body right before each edit and write it back with only those lines changed, because gh issue edit --body replaces the whole body and someone else may have edited it meanwhile. The goal is met only when the work is done and every box you could verify is ticked.'
LOG_INSTRUCTION='Progress log: keep a progress log in .jikkyo/progress.md on this branch, so an interrupted run can be resumed from it. Each time you mark a todo completed, update the log, commit it, and run a plain git push. Keep the log in this fixed shape: first the header lines "issue: <issue URL>", "branch: <this branch>", "updated: <ISO 8601 time>", and "next: <the next step, one line>"; then a "## Todos" section with one task-list line per todo, "- [x] <todo> (<short commit hash>)" once it is completed and "- [ ] <todo>" until then; then a "## Verified task-list items" section with one "- <item>: <how it was verified>" line per box you ticked on the issue; then a "## Dead ends and decisions" section with what did not work or what you decided, and why. Never put tokens, secrets, environment values, or command output in the log. As the last step, right before you open the pull request (or mark it ready for review), delete .jikkyo/progress.md in one ordinary commit and push it, so the log never reaches the base branch.'

usage() {
  echo "usage: launch.sh '<https://github.com/<owner>/<repo>/issues/<N>>'" >&2
  exit 2
}

[ "$#" -eq 1 ] || usage
url="$1"

re='^https://github\.com/([A-Za-z0-9][A-Za-z0-9-]*)/([A-Za-z0-9._-]+)/issues/([1-9][0-9]*)$'
if ! [[ "$url" =~ $re ]]; then
  echo "launch.sh: not a GitHub issue URL: $url" >&2
  usage
fi
owner="${BASH_REMATCH[1]}"
repo="${BASH_REMATCH[2]}"
num="${BASH_REMATCH[3]}"

# --worktree needs a git repository, and the child's PR has to land in the
# issue's repository, so one of this checkout's remotes must point at it.
common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || {
  echo "launch.sh: not inside a git repository" >&2
  exit 2
}
root="$(dirname "$common")"
want="$(printf '%s/%s' "$owner" "${repo%.git}" | tr '[:upper:]' '[:lower:]')"
match=""
while read -r _ remote_url _; do
  r="$(printf '%s' "$remote_url" | tr '[:upper:]' '[:lower:]')"
  r="${r%/}"
  r="${r%.git}"
  case "$r" in
    https://github.com/"$want" | ssh://git@github.com/"$want" | git@github.com:"$want") match=1 ;;
  esac
done < <(git -C "$root" remote -v 2>/dev/null)
if [ -z "$match" ]; then
  echo "launch.sh: no remote of $root points at github.com/$owner/$repo" >&2
  exit 2
fi

# Name the worktree ourselves: nothing in the stream is documented to give a
# generated name back, and the timestamp keeps a re-run from colliding with a
# worktree an earlier run kept.
name="jikkyo-${num}-$(date '+%Y%m%d-%H%M%S')"
echo "jikkyo: worktree name ${name}"
echo "jikkyo: worktree path ${root}/.claude/worktrees/${name}"
echo "jikkyo: worktree branch worktree-${name}"

cd "$root" || exit 2

# The goal condition is the issue URL verbatim, then the fixed todo, tick, and
# log instructions. --disallowedTools takes the rest of the command line, so it
# stays last. stdin is /dev/null: `claude -p`
# otherwise waits for piped input, and the child has no business reading ours.
CLAUDE_CODE_ENABLE_TODO_TOOLS=1 claude -p "/goal ${url} ${TODO_INSTRUCTION} ${TICK_INSTRUCTION} ${LOG_INSTRUCTION}" \
  --worktree "$name" \
  --output-format stream-json \
  --verbose \
  --permission-mode auto \
  --disallowedTools "${DENY_RULES[@]}" \
  < /dev/null \
  | "$HERE/report.sh" "$url"
