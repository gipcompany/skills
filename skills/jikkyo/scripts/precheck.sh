#!/usr/bin/env bash
#
# precheck.sh — decide whether a new jikkyo run may start on an issue, or which
# earlier run to resume, from the issue's comments alone, so the answer is the
# same on every machine.
#
#   gh api --paginate repos/<o>/<r>/issues/<N>/comments \
#     | precheck.sh --author <login> [--now <epoch>] [--force | --resume <N>]
#
# Prints exactly one decision line:
#
#   start                  no live run; start the new one.
#   refuse <comment URL>   a live run is reporting there; do not start.
#   rewrite <id> [<id>…]   rewrite each of these status comments to
#                          `interrupted` (see --payload), then start.
#
# With --resume <N> (<N> is the issue's number) the question is whether an
# earlier run can be resumed, and the lines are:
#
#   refuse <comment URL>   as above: a live run is reporting there.
#   rewrite <id> [<id>…]   as above; after rewriting, run the same check
#                          again, so a run that died at `running` can be the
#                          one resumed.
#   resume <branch> <id>   resume the branch named in status comment <id>:
#                          the latest `interrupted` or `failed` one counted,
#                          leaving out a branch with a later `finished` one.
#   none                   nothing to resume: no such comment, or the latest
#                          one names no branch, or a branch of another issue.
#
# The branch printed with `resume` is always exactly
# `worktree-jikkyo-<N>-<8 digits>-<6 digits>` and the id is all digits: that
# is the only text from the comments that leaves this script for a command line.
#
# Only jikkyo's own status comments count: a body that starts with the hidden
# `<!-- jikkyo:status v=1 state=… [branch=…] -->` marker AND an author (`user.login`)
# equal to --author. A `running` comment whose `updated_at` is 15 minutes old
# or more is stale: the heartbeat refreshes a live one every 5 minutes. With
# --force nothing blocks, and every `running` comment is rewritten.
#
#   gh api repos/<o>/<r>/issues/comments/<id> | precheck.sh --payload
#
# prints the PATCH payload ({"body": …}) that turns that `running` comment into
# an `interrupted` one, and exits 1 if the comment is not in state `running`.
# It rewrites the visible text in English or in Japanese (report.sh writes
# Japanese on an issue written in Japanese), including comments written before
# there was a Japanese form; the state is read from the marker alone, which is
# English in both, so the decision lines above do not depend on the language.
#
# Exit status: 0 with a decision, 1 as above, 2 on bad input, including
# empty input or anything that is not a list of comment arrays.
#
set -uo pipefail

STALE_AFTER=900

usage() {
  echo "usage: precheck.sh --author <login> [--now <epoch>] [--force | --resume <N>] < comments.json" >&2
  echo "       precheck.sh --payload < comment.json" >&2
  exit 2
}

command -v jq >/dev/null 2>&1 || { echo "precheck.sh: jq is required" >&2; exit 2; }

author="" now="" force=false payload=false resume_num="" resuming=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --author) [ "$#" -ge 2 ] || usage; author="$2"; shift 2 ;;
    --now) [ "$#" -ge 2 ] || usage; now="$2"; shift 2 ;;
    --force) force=true; shift ;;
    --payload) payload=true; shift ;;
    --resume) [ "$#" -ge 2 ] || usage; resume_num="$2"; resuming=true; shift 2 ;;
    *) usage ;;
  esac
done

# The marker is the only machine-readable state; the visible text is for people.
# report.sh writes the run's branch after the state (`state=running
# branch=worktree-jikkyo-<N>-<YYYYmmdd>-<HHMMSS> -->`); comments written
# before that have no `branch=` field. Both forms are read.
MARKER_RE='^<!-- jikkyo:status v=1 state=(?<state>[a-z]+)(?: branch=(?<branch>worktree-jikkyo-[0-9]+-[0-9]{8}-[0-9]{6}))? -->'

if [ "$payload" = true ]; then
  if [ -n "$author" ] || [ -n "$now" ] || [ "$force" = true ] || [ "$resuming" = true ]; then usage; fi
  out="$(jq -c --arg re "$MARKER_RE" '
    if type == "array" then .[0] else . end
    | (.body // "") as $b
    | ($b | capture($re).state? // null) as $s
    | if $s != "running" then empty
      else {body: ($b
        # Only the state changes; a `branch=` field after it is kept as is.
        | sub("^<!-- jikkyo:status v=1 state=running(?<r>(?: branch=[^ ]+)?) -->"; "<!-- jikkyo:status v=1 state=interrupted\(.r) -->")
        | sub("### jikkyo · running"; "### jikkyo · interrupted")
        # A dead run keeps no forward-looking estimate: drop the heading
        # suffix (` · ~` occurs nowhere else) and empty the Remaining cell,
        # whose label is `Remaining`, or `Remaining (est.)` in older comments.
        | sub(" · ~[^\\n]*"; "")
        | sub("\\| State \\| running \\|"; "| State | interrupted |")
        | sub("\\| (?<l>Remaining(?: \\(est\\.\\))?) \\|[^\\n]*"; "| \(.l) |  |")
        # The Japanese form, written on an issue in Japanese: the same
        # rewrites. The marker is English in both; only the visible words
        # differ, and a comment matches one set of these or the other.
        | sub("### jikkyo · 実行中"; "### jikkyo · 中断")
        | sub(" · 残り ~[^\\n]*"; "")
        | sub("\\| 状態 \\| 実行中 \\|"; "| 状態 | 中断 |")
        | sub("\\| 残り \\|[^\\n]*"; "| 残り |  |"))}
      end' 2>/dev/null)" || usage
  [ -n "$out" ] || { echo "precheck.sh: that comment is not a running jikkyo status comment" >&2; exit 1; }
  printf '%s\n' "$out"
  exit 0
fi

[ -n "$author" ] || usage
[ -n "$now" ] || now="$(date '+%s')"
case "$now" in '' | *[!0-9]*) usage ;; esac
# A forced resume would take a live run's branch out from under it.
if [ "$resuming" = true ]; then
  [ "$force" = false ] || usage
  [[ "$resume_num" =~ ^[1-9][0-9]*$ ]] || usage
fi
input="$(cat)"

# `gh api --paginate` prints one array per page; slurp and flatten them. A
# failed listing prints nothing or an error object, and must not read as "no
# comments": that would switch the check off.
if ! jq -e -s 'length > 0 and all(.[]; type == "array")' >/dev/null 2>&1 <<<"$input"; then
  echo "precheck.sh: expected the issue's comments as JSON arrays (did the gh call fail?)" >&2
  exit 2
fi
jq -r -s --arg re "$MARKER_RE" --arg author "$author" --argjson now "$now" \
  --argjson force "$force" --argjson stale "$STALE_AFTER" --arg resume_num "$resume_num" '
  [ flatten(1)[]
    | select(type == "object" and .user.login? == $author)
    | ((.body // "") | capture($re)? // null) as $m
    | select($m != null)
    | {id, url: .html_url, state: $m.state, branch: $m.branch,
       age: ($now - ((.updated_at // .created_at) | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601))} ] as $counted
  | [ $counted[] | select(.state == "running") ] as $running
  | [ $running[] | select(.age < $stale) ] as $live
  | ("rewrite " + ($running | map(.id | tostring) | join(" "))) as $rewrite
  | if $resume_num != "" then
      if $live != [] then "refuse " + $live[0].url
      elif $running != [] then $rewrite
      else
        # Comment ids grow with creation, so the largest is the latest run.
        # Earlier comments are never edited, so a branch that was resumed and
        # then finished still has its old `interrupted` comment: a `finished`
        # comment for the same branch, posted later, takes the branch out.
        ([ $counted[] | select(.state == "finished" and .branch != null and (.id | type) == "number") ]) as $done
        | ([ $counted[] | select(.state == "interrupted" or .state == "failed")
           | select((.id | type) == "number")
           | . as $c | select(all($done[]; .branch != $c.branch or .id < $c.id)) ] | max_by(.id)) as $last
        | if $last == null then "none"
          elif ($last.branch // "" | test("^worktree-jikkyo-" + $resume_num + "-[0-9]{8}-[0-9]{6}$"))
            then "resume " + $last.branch + " " + ($last.id | tostring)
          else "none" end
      end
    elif $running == [] then "start"
    elif $force then $rewrite
    elif $live != [] then "refuse " + $live[0].url
    else $rewrite
    end' <<<"$input" || usage
