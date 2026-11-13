#!/usr/bin/env bash
#
# precheck.sh — decide whether a new jikkyo run may start on an issue, from the
# issue's comments alone, so the answer is the same on every machine.
#
#   gh api --paginate repos/<o>/<r>/issues/<N>/comments \
#     | precheck.sh --author <login> [--now <epoch>] [--force]
#
# Prints exactly one decision line:
#
#   start                  no live run; start the new one.
#   refuse <comment URL>   a live run is reporting there; do not start.
#   rewrite <id> [<id>…]   rewrite each of these status comments to
#                          `interrupted` (see --payload), then start.
#
# Only jikkyo's own status comments count: a body that starts with the hidden
# `<!-- jikkyo:status v=1 state=… -->` marker AND an author (`user.login`)
# equal to --author. A `running` comment whose `updated_at` is 15 minutes old
# or more is stale: the heartbeat refreshes a live one every 5 minutes. With
# --force nothing blocks, and every `running` comment is rewritten.
#
#   gh api repos/<o>/<r>/issues/comments/<id> | precheck.sh --payload
#
# prints the PATCH payload ({"body": …}) that turns that `running` comment into
# an `interrupted` one, and exits 1 if the comment is not in state `running`.
#
# Exit status: 0 with a decision, 1 as above, 2 on bad input, including
# empty input or anything that is not a list of comment arrays.
#
set -uo pipefail

STALE_AFTER=900

usage() {
  echo "usage: precheck.sh --author <login> [--now <epoch>] [--force] < comments.json" >&2
  echo "       precheck.sh --payload < comment.json" >&2
  exit 2
}

command -v jq >/dev/null 2>&1 || { echo "precheck.sh: jq is required" >&2; exit 2; }

author="" now="" force=false payload=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --author) [ "$#" -ge 2 ] || usage; author="$2"; shift 2 ;;
    --now) [ "$#" -ge 2 ] || usage; now="$2"; shift 2 ;;
    --force) force=true; shift ;;
    --payload) payload=true; shift ;;
    *) usage ;;
  esac
done

# The marker is the only machine-readable state; the visible text is for people.
MARKER_RE='^<!-- jikkyo:status v=1 state=(?<state>[a-z]+) -->'

if [ "$payload" = true ]; then
  if [ -n "$author" ] || [ -n "$now" ] || [ "$force" = true ]; then usage; fi
  out="$(jq -c --arg re "$MARKER_RE" '
    if type == "array" then .[0] else . end
    | (.body // "") as $b
    | ($b | capture($re).state? // null) as $s
    | if $s != "running" then empty
      else {body: ($b
        | sub("^<!-- jikkyo:status v=1 state=running -->"; "<!-- jikkyo:status v=1 state=interrupted -->")
        | sub("### jikkyo · running"; "### jikkyo · interrupted")
        | sub("\\| State \\| running \\|"; "| State | interrupted |"))}
      end' 2>/dev/null)" || usage
  [ -n "$out" ] || { echo "precheck.sh: that comment is not a running jikkyo status comment" >&2; exit 1; }
  printf '%s\n' "$out"
  exit 0
fi

[ -n "$author" ] || usage
[ -n "$now" ] || now="$(date '+%s')"
case "$now" in '' | *[!0-9]*) usage ;; esac
input="$(cat)"

# `gh api --paginate` prints one array per page; slurp and flatten them. A
# failed listing prints nothing or an error object, and must not read as "no
# comments": that would switch the check off.
if ! jq -e -s 'length > 0 and all(.[]; type == "array")' >/dev/null 2>&1 <<<"$input"; then
  echo "precheck.sh: expected the issue's comments as JSON arrays (did the gh call fail?)" >&2
  exit 2
fi
jq -r -s --arg re "$MARKER_RE" --arg author "$author" --argjson now "$now" \
  --argjson force "$force" --argjson stale "$STALE_AFTER" '
  [ flatten(1)[]
    | select(type == "object" and .user.login? == $author)
    | ((.body // "") | capture($re).state? // null) as $s
    | select($s == "running")
    | {id, url: .html_url,
       age: ($now - ((.updated_at // .created_at) | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601))} ] as $running
  | if $running == [] then "start"
    elif $force then "rewrite " + ($running | map(.id | tostring) | join(" "))
    elif any($running[]; .age < $stale) then "refuse " + ([$running[] | select(.age < $stale)][0].url)
    else "rewrite " + ($running | map(.id | tostring) | join(" "))
    end' <<<"$input" || usage
