#!/usr/bin/env bash
#
# report.sh — read a `claude -p --output-format stream-json` stream on stdin
# and keep one status comment on the GitHub issue up to date while it runs.
#
#   claude -p ... --output-format stream-json --verbose | report.sh '<issue URL>'
#
# It creates the status comment at once, rewrites it in place by comment id
# (never --edit-last), and writes:
#   - start and end immediately,
#   - todo changes at most once every 30 seconds (held changes are written at
#     the next allowed slot, and anything pending is written at the end),
#   - a heartbeat every 5 minutes, so a long silent stretch does not look stale.
#
# Progress comes from the stream alone: TaskCreate results give task ids,
# TaskUpdate sets their status, and % = completed / tasks not deleted. With no
# tasks the comment shows the turn count instead, never a made-up number.
# While running, once a todo is completed, a `Remaining` row (and a
# ` · ~<duration> left` heading suffix) gives elapsed / completed * (total -
# completed), the run-wide rate; otherwise that row is present but empty.
#
# The final state is `finished` (a non-error result line), `failed` (an error
# result line), or `interrupted` (no result line, or SIGTERM/SIGHUP/SIGINT).
# After the final write it prints the child's final message for the parent
# session: the `result` text on success, the `errors` on an error_* subtype.
#
# Language: before the first write it reads the issue's title and body with
# `gh api` and writes the visible text in Japanese (`ja`) if they contain any
# hiragana, katakana, or kanji, else in English (`en`). The issue's text goes
# from gh to jq on a pipe and only `ja` or `en` comes back: none of it reaches
# a command line or the comment. A failed fetch gives `en`. The choice is made
# once and printed as `jikkyo: language <ja|en>`. The hidden marker, the state
# values in it, and the number and duration formats are the same in both.
#
# Tuning, for tests: JIKKYO_TODO_INTERVAL (30), JIKKYO_HEARTBEAT_INTERVAL (300),
# JIKKYO_TICK (1, seconds between scheduler passes), JIKKYO_MIN_GAP (1, seconds
# between two writes), JIKKYO_CLOCK_FILE (read "now" in epoch seconds from this
# file instead of the system clock).
#
set -uo pipefail

TODO_INTERVAL="${JIKKYO_TODO_INTERVAL:-30}"
HEARTBEAT_INTERVAL="${JIKKYO_HEARTBEAT_INTERVAL:-300}"
TICK="${JIKKYO_TICK:-1}"
MIN_GAP="${JIKKYO_MIN_GAP:-1}"

usage() {
  echo "usage: ... | report.sh '<https://github.com/<owner>/<repo>/issues/<N>>'" >&2
  exit 2
}
[ "$#" -eq 1 ] || usage
re='^https://github\.com/([A-Za-z0-9][A-Za-z0-9-]*)/([A-Za-z0-9._-]+)/issues/([1-9][0-9]*)$'
[[ "$1" =~ $re ]] || usage
owner="${BASH_REMATCH[1]}"
repo="${BASH_REMATCH[2]}"
num="${BASH_REMATCH[3]}"

command -v jq >/dev/null 2>&1 || { echo "report.sh: jq is required" >&2; exit 2; }

now() {
  if [ -n "${JIKKYO_CLOCK_FILE:-}" ]; then cat "$JIKKYO_CLOCK_FILE"; else date '+%s'; fi
}

# Local time with an explicit UTC offset; GitHub does not convert times written
# in comment text, so the offset is what lets a reader elsewhere convert it.
fmt_time() {
  # GNU first: on GNU date, `-r <n>` would read the mtime of a file named <n>.
  date -d "@$1" '+%Y-%m-%d %H:%M:%S %z' 2>/dev/null || date -r "$1" '+%Y-%m-%d %H:%M:%S %z'
}

fmt_duration() {
  local s="$1" h m
  [ "$s" -lt 0 ] && s=0
  h=$((s / 3600)); m=$((s % 3600 / 60)); s=$((s % 60))
  if [ "$h" -gt 0 ]; then printf '%dh %02dm %02ds' "$h" "$m" "$s"
  elif [ "$m" -gt 0 ]; then printf '%dm %02ds' "$m" "$s"
  else printf '%ds' "$s"; fi
}

# Hiragana, katakana (with the phonetic extensions and the halfwidth forms),
# and kanji (CJK unified ideographs, extension A, compatibility ideographs).
# shellcheck disable=SC2016  # jq program
LANG_FILTER='
  ((.title // "") + "\n" + (.body // "")) as $t
  | if ($t | type) == "string"
       and ($t | test("[\u3040-\u30ff\u31f0-\u31ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\uff66-\uff9f]"))
    then "ja" else "en" end
'

# detect_lang: print `ja` or `en` for the issue. Anything that goes wrong
# (gh fails, the answer is not an issue object) gives `en`.
detect_lang() {
  local l
  l="$(gh api "repos/${owner}/${repo}/issues/${num}" 2>/dev/null \
       | jq -r "if type == \"object\" then (try (${LANG_FILTER}) catch \"en\") else \"en\" end" 2>/dev/null)"
  case "$l" in ja) echo ja ;; *) echo en ;; esac
}

# The visible text in each language. The marker always uses the English state.
set_labels() {
  if [ "$1" = ja ]; then
    L_FIELD="項目" L_VALUE="値" L_STATE="状態" L_STARTED="開始" L_ENDED="終了"
    L_PROGRESS="進捗" L_TURNS="ターン数" L_ELAPSED="経過" L_REMAINING="残り"
    L_ESTIMATE="（推定）" L_LEFT_PRE=" · 残り ~" L_LEFT_POST=""
    L_TURN_ONE="1 ターン" L_TURN_MANY=" ターン"
  else
    L_FIELD="Field" L_VALUE="Value" L_STATE="State" L_STARTED="Started" L_ENDED="Ended"
    L_PROGRESS="Progress" L_TURNS="Turns" L_ELAPSED="Elapsed" L_REMAINING="Remaining"
    L_ESTIMATE=" (estimate)" L_LEFT_PRE=" · ~" L_LEFT_POST=" left"
    L_TURN_ONE="1 turn" L_TURN_MANY=" turns"
  fi
}
state_word() {
  if [ "$LANG_CODE" = ja ]; then
    case "$1" in running) echo "実行中" ;; finished) echo "完了" ;; failed) echo "失敗" ;;
      interrupted) echo "中断" ;; *) echo "$1" ;; esac
  else echo "$1"; fi
}

# ---------------------------------------------------------------------------
# Parser: one jq process folds the whole stream and prints the state after
# every line. Lines that are not JSON, and events whose shape the step does not
# expect, are skipped rather than ending the run: if jq died, report.sh would
# exit and the child would die of SIGPIPE.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2016  # jq program: $e and $u are jq variables
PARSER='
def text_of: if type == "string" then . elif type == "array" then map(.text? // "") | join("\n") else "" end;
def step($e):
  if $e.type == "assistant" then
    (if ($e.parent_tool_use_id == null) and (($e.message.id // "") != .lastmsg)
     then .turns += 1 | .lastmsg = ($e.message.id // "") else . end)
    | reduce (($e.message.content // []) | arrays | .[]
              | select(type == "object" and .type == "tool_use" and (.id | type) == "string")) as $u (.;
        if $u.name == "TaskCreate" then .todo = true | .pend[$u.id] = {k: "c"}
        elif $u.name == "TaskUpdate" then .todo = true
          | .pend[$u.id] = {k: "u", t: ($u.input.taskId | tostring), s: $u.input.status}
        else . end)
  elif $e.type == "user" then
    reduce (($e.message.content // []) | arrays | .[]
            | select(type == "object" and .type == "tool_result" and (.tool_use_id | type) == "string")) as $r (.;
      .pend[$r.tool_use_id] as $p
      | if $p == null then .
        else del(.pend[$r.tool_use_id])
        | if $r.is_error == true then .
          elif $p.k == "c" then
            ((($r.content | text_of) | capture("Task #(?<n>[0-9]+)").n)
              // (($e.tool_use_result | objects | .task | objects | .id) // null
                  | if . == null then null else tostring end)) as $id
            | if $id == null then . else .tasks[$id] = "pending" end
          elif $p.s == "deleted" then del(.tasks[$p.t])
          elif ($p.s != null) and (.tasks | has($p.t)) then .tasks[$p.t] = $p.s
          else . end
        end)
  elif $e.type == "result" then
    .result = {subtype: ($e.subtype // ""), is_error: ($e.is_error // false),
               text: ($e.result // null), errors: ($e.errors // null)}
  else . end;
foreach (inputs | fromjson? // empty | select(type == "object")) as $e
  ({tasks: {}, pend: {}, turns: 0, lastmsg: null, todo: false, result: null};
   (try step($e) catch .);
   {tasks, pend, turns, lastmsg, todo, result})
| {done: ([.tasks[] | select(. == "completed")] | length), total: (.tasks | length),
   turns, result, tasks, pend, lastmsg, todo}
'

work="$(mktemp -d "${TMPDIR:-/tmp}/jikkyo-report.XXXXXX")" || exit 1
state_file="$work/state.json"
printf '%s\n' '{"done":0,"total":0,"turns":0,"result":null}' > "$state_file"

start_ts="$(now)"
comment_id=""
comment_url=""
last_write=""        # clock time of the last write
last_write_real=""   # $SECONDS at the last write, for the 1-second gap
last_key=""          # progress shown by the last write
final_done=""

# body <state> <state.json contents> <end ts or empty>
body() {
  local st="$1" json="$2" end_ts="$3" t completed total turns heading label value ended elapsed
  local secs eta="" eta_cell="" eta_suffix="" word
  t="$(now)"
  completed="$(jq -r '.done' <<<"$json")"
  total="$(jq -r '.total' <<<"$json")"
  turns="$(jq -r '.turns' <<<"$json")"
  if [ "$total" -gt 0 ]; then
    value="$((completed * 100 / total))%"
    heading="$value"
    label="$L_PROGRESS"
  else
    value="$turns"
    heading="${turns}${L_TURN_MANY}"
    [ "$turns" = 1 ] && heading="$L_TURN_ONE"
    label="$L_TURNS"
  fi
  ended=""
  if [ -n "$end_ts" ]; then ended="$(fmt_time "$end_ts")"; t="$end_ts"; fi
  secs=$((t - start_ts))
  elapsed="$(fmt_duration "$secs")"
  # Estimated time remaining: the run-wide rate so far, applied to the todos
  # left. Only while running, and only with at least one completed todo; with
  # no rate to go on the cell stays empty rather than showing a made-up time.
  if [ "$st" = running ] && [ "$total" -gt 0 ] && [ "$completed" -gt 0 ]; then
    [ "$secs" -lt 0 ] && secs=0
    eta="$(fmt_duration $((secs * (total - completed) / completed)))"
    eta_cell="~${eta}${L_ESTIMATE}"
    eta_suffix="${L_LEFT_PRE}${eta}${L_LEFT_POST}"
  fi
  word="$(state_word "$st")"
  printf '<!-- jikkyo:status v=1 state=%s -->\n' "$st"
  printf '### jikkyo · %s · %s%s\n\n' "$word" "$heading" "$eta_suffix"
  printf '| %s | %s |\n| --- | --- |\n' "$L_FIELD" "$L_VALUE"
  printf '| %s | %s |\n' "$L_STATE" "$word"
  printf '| %s | %s |\n' "$L_STARTED" "$(fmt_time "$start_ts")"
  printf '| %s | %s |\n' "$L_ENDED" "$ended"
  printf '| %s | %s |\n' "$label" "$value"
  printf '| %s | %s |\n' "$L_ELAPSED" "$elapsed"
  printf '| %s | %s |\n' "$L_REMAINING" "$eta_cell"
}

# write <state> [end ts]: create the comment on the first call, PATCH it by id
# after that. Writes are serial and at least MIN_GAP seconds apart. A signal
# that arrives mid-write is held until the write is done, so the comment id is
# never lost between the POST and the assignment.
in_write=""
held_signal=""
write() {
  in_write=1
  _write "$@"
  in_write=""
  if [ -n "$held_signal" ]; then on_signal "$held_signal"; fi
}
_write() {
  local st="$1" end_ts="${2:-}" json payload out
  json="$(cat "$state_file")"
  payload="$(jq -n --arg b "$(body "$st" "$json" "$end_ts")" '{body: $b}')"
  # $SECONDS counts whole seconds, so a difference of 1 can be milliseconds.
  if [ -n "$last_write_real" ] && [ $((SECONDS - last_write_real)) -le "$MIN_GAP" ]; then
    sleep "$MIN_GAP"
  fi
  if [ -z "$comment_id" ]; then
    out="$(printf '%s' "$payload" | gh api -X POST "repos/${owner}/${repo}/issues/${num}/comments" \
      --input - --jq '[.id, .html_url] | @tsv' 2>/dev/null)"
    if [ -n "$out" ]; then
      comment_id="${out%%$'\t'*}"
      comment_url="${out#*$'\t'}"
      echo "jikkyo: status comment ${comment_url}"
    else
      echo "jikkyo: could not create the status comment; will retry at the next write" >&2
    fi
  else
    printf '%s' "$payload" | gh api -X PATCH "repos/${owner}/${repo}/issues/comments/${comment_id}" \
      --input - >/dev/null 2>&1 \
      || echo "jikkyo: could not update the status comment ${comment_id}" >&2
  fi
  last_write="$(now)"
  last_write_real="$SECONDS"
  last_key="$(jq -c '[.done, .total]' <<<"$json")"
}

print_final_message() {
  local json msg
  json="$(cat "$state_file")"
  if [ "$(jq -r '.result == null' <<<"$json")" = true ]; then
    echo "jikkyo: no final message (the stream ended without a result line)"
    return
  fi
  msg="$(jq -r '.result | if .subtype == "success" then (.text // "")
         else ((.errors // []) | if type == "array" then map(tostring) | join("\n") else tostring end) end' <<<"$json")"
  # An empty result is real: a /goal loop that hits the stop-hook block cap
  # ends with subtype success and no text. Say so instead of printing nothing.
  if [ -z "$(printf '%s' "$msg" | tr -d '[:space:]')" ]; then
    echo "jikkyo: final message is empty (the result line carried no text)"
    return
  fi
  echo "jikkyo: final message:"
  printf '%s\n' "$msg"
}

final_state() {
  jq -r '.result | if . == null then "interrupted"
         elif .is_error == true or .subtype != "success" then "failed"
         else "finished" end' "$state_file"
}

parser_pid=""
finish() {
  local st="$1"
  [ -n "$final_done" ] && return
  final_done=1
  # The final write and the hand-over run to the end, whatever arrives now.
  trap '' TERM HUP INT
  [ -n "$parser_pid" ] && kill "$parser_pid" 2>/dev/null
  _write "$st" "$(now)"
  echo "jikkyo: state ${st}"
  print_final_message
  rm -rf "$work"
}

on_signal() {
  if [ -n "$in_write" ]; then held_signal="$1"; return; fi
  finish interrupted
  exit "$1"
}
trap 'on_signal 143' TERM
trap 'on_signal 129' HUP
trap 'on_signal 130' INT

LANG_CODE=en; set_labels en   # until the fetch below has answered
LANG_CODE="$(detect_lang)"
set_labels "$LANG_CODE"
echo "jikkyo: language ${LANG_CODE}"

write running

# The parser runs in the background so the scheduler can keep its own time
# (bash 3.2's `read -t` cannot tell a timeout from end of input). Each state
# is written to a temp file and renamed into place, so a reader never sees a
# half-written one. A background job's stdin is /dev/null unless it is
# redirected, so the stream is handed over on fd 3.
exec 3<&0
(
  jq -R -n -c --unbuffered "$PARSER" | while IFS= read -r s; do
    printf '%s\n' "$s" > "$state_file.tmp" && mv "$state_file.tmp" "$state_file"
  done
  : > "$work/eof"
) <&3 &
parser_pid=$!

while [ ! -e "$work/eof" ]; do
  sleep "$TICK"
  [ -e "$work/eof" ] && break
  t="$(now)"
  key="$(jq -c '[.done, .total]' "$state_file" 2>/dev/null)" || continue
  if [ "$key" != "$last_key" ] && [ $((t - last_write)) -ge "$TODO_INTERVAL" ]; then
    write running
  elif [ $((t - last_write)) -ge "$HEARTBEAT_INTERVAL" ]; then
    write running
  fi
done
wait "$parser_pid" 2>/dev/null
parser_pid=""

finish "$(final_state)"
