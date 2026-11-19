#!/usr/bin/env bash
#
# report.sh — read a `claude -p --output-format stream-json` stream on stdin
# and keep one status comment on the GitHub issue up to date while it runs.
#
#   claude -p ... --output-format stream-json --verbose \
#     | report.sh [--session <session id>] '<issue URL>' [worktree-jikkyo-<N>-<YYYYmmdd>-<HHMMSS> [<comment id>]]
#
# --session gives the id of the session that launched (or resumed) the run
# (launch.sh passes it). It must have the exact shape of a Claude Code session
# id, a UUID, or report.sh exits 2 before it writes anything. It goes into the
# state file only (see below), so the status line shows the run in that
# session alone.
#
# The optional second argument is the run's branch (launch.sh passes it). It
# must be `worktree-jikkyo-<N>-<8 digits>-<6 digits>`, with <N> the issue's
# number, or report.sh exits 2 before it writes anything. It goes into the
# hidden marker after `state=` (`... state=running branch=<name> -->`), so a
# later run can find this one's branch, and into a visible `Branch` row. With
# no branch the marker has no `branch=` field and the row is empty.
#
# The optional third argument, on a resumed run, is the numeric id of the
# earlier run's status comment (launch.sh --resume passes it). It must match
# ^[1-9][0-9]*$ (digits, no leading zero), or report.sh exits 2 before it
# writes anything. It adds a `Resumed from` row (`再開元`) linking that
# comment, built from the validated owner, repository, and issue number. The
# earlier comment is not touched.
#
# It creates the status comment at once, rewrites it in place by comment id
# (never --edit-last), and writes:
#   - start and end immediately,
#   - todo changes at most once every 30 seconds (held changes are written at
#     the next allowed slot, and anything pending is written at the end); a
#     todo change is any change in the todo list (an id, a subject as cut for
#     display, or a status), not only in the counts, including one in a todo
#     the 50-line cap hides,
#   - a heartbeat every 5 minutes, so a long silent stretch does not look stale.
#
# Progress comes from the stream alone: TaskCreate results give task ids and
# subjects, TaskUpdate sets their status (and renames them), and % =
# completed / tasks not deleted. With no tasks the comment shows the turn
# count instead, never a made-up number. The comment ends with the todo list
# itself, in a collapsed section (see TODOS below); the status line's state
# file (<N>.json, below) never holds it.
# While running, once a todo is completed, a `Remaining` row (and a
# ` · ~<duration> left` heading suffix) gives elapsed / completed * (total -
# completed), the run-wide rate; otherwise that row is present but empty.
#
# The final state is `finished` (a non-error result line, and every todo that
# is not deleted completed), `incomplete` (a non-error result line, but some
# todo not completed), `failed` (an error result line), or `interrupted` (no
# result line, or SIGTERM/SIGHUP/SIGINT).
# After the final write it prints the child's final message for the parent
# session: the `result` text on success, the `errors` on an error_* subtype.
#
# Language: before the first write it reads the issue's title and body with
# `gh api` and writes the visible text in Japanese (`ja`) if they contain any
# hiragana, katakana, or kanji outside code (fenced code blocks and code
# spans, see LANG_FILTER), else in English (`en`). The issue's text goes
# from gh to jq on a pipe and only `ja` or `en` comes back: none of it reaches
# a command line or the comment. A failed fetch gives `en`. The choice is made
# once and printed as `jikkyo: language <ja|en>`. The hidden marker, the state
# values in it, and the number and duration formats are the same in both.
#
# State file: every time it writes the status comment, and at exit, it also
# writes <git common dir>/jikkyo/<N>.json (the common dir of the checkout it
# runs in, shared by all its worktrees, never committed) for the status line
# (scripts/statusline.sh). It is written to a temp file in the same directory
# and renamed into place, so a reader never sees half of one. It holds only
# numbers, the state, the language, the session id, and URLs built from
# validated parts:
#
#   {"v":1,"issue":"<issue URL>","number":<N>,"state":"running","done":3,
#    "total":5,"turns":12,"started":<epoch>,"updated":<epoch>,"eta_secs":720,
#    "lang":"en","session":"<session id>","comment":"<status comment URL>"}
#
# eta_secs is the remaining-time estimate in seconds, null when there is none;
# session and comment are null when unknown. Nothing deletes the file; the next
# run of the issue overwrites it. Outside a git repository, when the directory
# cannot be written or is a symlink, or when <N>.json is a directory, there is
# no state file and the run goes on. The file is a convenience for the status
# line, not a record: the status comment is the record, and anything that can
# write to the git common dir (the child included) can write this file too.
#
# Tuning, for tests: JIKKYO_TODO_INTERVAL (30), JIKKYO_HEARTBEAT_INTERVAL (300),
# JIKKYO_TICK (1, seconds between scheduler passes), JIKKYO_MIN_GAP (1, seconds
# between two writes), JIKKYO_CLOCK_FILE (read "now" in epoch seconds from this
# file instead of the system clock), JIKKYO_NO_PERL (1: put the state file in
# place without perl, see place()).
#
set -uo pipefail

TODO_INTERVAL="${JIKKYO_TODO_INTERVAL:-30}"
HEARTBEAT_INTERVAL="${JIKKYO_HEARTBEAT_INTERVAL:-300}"
TICK="${JIKKYO_TICK:-1}"
MIN_GAP="${JIKKYO_MIN_GAP:-1}"

usage() {
  echo "usage: ... | report.sh [--session <session id>] '<https://github.com/<owner>/<repo>/issues/<N>>' [worktree-jikkyo-<N>-<YYYYmmdd>-<HHMMSS> [<comment id>]]" >&2
  exit 2
}
session=""
if [ "$#" -ge 1 ] && [ "$1" = --session ]; then
  [ "$#" -ge 2 ] || usage
  session="$2"
  sid_re='^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
  if ! [[ "$session" =~ $sid_re ]]; then
    echo "report.sh: not a session id: $session" >&2
    usage
  fi
  shift 2
fi
if [ "$#" -lt 1 ] || [ "$#" -gt 3 ]; then usage; fi
re='^https://github\.com/([A-Za-z0-9][A-Za-z0-9-]*)/([A-Za-z0-9._-]+)/issues/([1-9][0-9]*)$'
[[ "$1" =~ $re ]] || usage
owner="${BASH_REMATCH[1]}"
repo="${BASH_REMATCH[2]}"
num="${BASH_REMATCH[3]}"

# The branch is written into the marker and the comment, so only the exact
# shape launch.sh makes, for this issue's number, gets through.
branch="${2:-}"
if [ "$#" -ge 2 ]; then
  branch_re="^worktree-jikkyo-${num}-[0-9]{8}-[0-9]{6}\$"
  if ! [[ "$branch" =~ $branch_re ]]; then
    echo "report.sh: not a jikkyo branch for issue ${num}: $branch" >&2
    usage
  fi
fi

# The earlier run's status comment, on a resumed run: a numeric id only.
resumed_from="${3:-}"
if [ "$#" -eq 3 ] && ! [[ "$resumed_from" =~ ^[1-9][0-9]*$ ]]; then
  echo "report.sh: not a comment id: $resumed_from" >&2
  usage
fi

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

# The issue is `ja` if Japanese is left in its title or body once code is
# dropped, else `en`. Japanese is hiragana, katakana (with the phonetic
# extensions and the halfwidth forms), and kanji (CJK unified ideographs,
# extension A, compatibility ideographs). Code is dropped following the
# CommonMark rules for two constructs, so an English issue that quotes
# Japanese labels or output in code stays `en`:
#   - fenced code blocks, from the body only: a fence opens on a line with up
#     to 3 spaces of indent and a run of 3 or more backticks (with no backtick
#     after it on the line) or 3 or more tildes, and closes on a line with up
#     to 3 spaces of indent, a run of the same character at least as long, and
#     nothing after it but spaces or tabs. A fence that is never closed runs
#     to the end of the body. The fence lines go too.
#   - code spans, from the title and from each paragraph of what is left of
#     the body: a run of backticks closed by the next run of the same length,
#     across lines but not across a blank line. A run with no matching closer
#     is literal text, and so is a backtick after an odd number of
#     backslashes (an escaped one).
# Indented (4-space) code blocks, HTML <pre>/<code>, and fences that open on a
# blockquote or list-marker line (`> ```` or `- ````) are not dropped: their
# text counts as prose. Such a fence is followed to its closing line, so an
# indented closing line is not taken for a new fence that would run to the
# end of the body. So that a fence's backtick run does
# not pair with a later one as a code span, a line that is only a backtick
# fence after indent, `>`, or list markers loses that run first (unfence). A
# fence on a list item's continuation line, indented by up to 3 spaces, is a
# fence like any other and is dropped. The title and the body are cleaned
# apart, so a title that starts with ``` does not hide the body. Tokens are
# built with split and appended by index, never with scan, gsub, or +=,
# which jq 1.7 runs in quadratic time on a long body.
# shellcheck disable=SC2016  # jq program
LANG_FILTER='
  def jp: test("[぀-ヿㇰ-ㇿ㐀-䶿一-鿿豈-﫿ｦ-ﾟ]");
  def lines: split("\r") | join("") | split("\n");
  def oddbs:
    (split("\\") | reverse) as $r
    | ((first($r | to_entries[] | select(.value != "") | .key)) // ($r | length - 1)) % 2 == 1;
  def unfence:
    ((capture("^(?<p>[ \t]*(?:(?:>|[-+*]|[0-9]{1,9}[.)])[ \t]*)*)`{3,}(?<i>[^`]*)$")) // null) as $m
    | if $m == null then . else $m.p + $m.i end;
  def opener($m): $m != null and ($m.f[0:1] == "~" or ($m.i | test("`") | not));
  def closes($f): test("^[ \t]*(?:>[ \t]*)*" + $f[0:1] + "{" + ($f | length | tostring) + ",}[ \t]*$");
  def drop_fences:
    reduce lines[] as $l ({out: [], f: null, c: null};
      .f as $f | .c as $c
      | if $f != null then
        if ($l | test("^ {0,3}" + $f[0:1] + "{" + ($f | length | tostring) + ",}[ \t]*$"))
        then .f = null else . end
      elif $c != null then
        if ($l | closes($c)) then .c = null else .out[.out | length] = ($l | unfence) end
      else
        (($l | capture("^ {0,3}(?<f>`{3,}|~{3,})(?<i>.*)$")) // null) as $m
        | if opener($m) then .f = $m.f
          else
            (($l | capture("^(?<p>[ \t]*(?:(?:>|[-+*]|[0-9]{1,9}[.)])[ \t]*)+)(?<f>`{3,}|~{3,})(?<i>.*)$")) // null) as $n
            | if opener($n) then .c = $n.f | .out[.out | length] = $n.p + $n.i
              else .out[.out | length] = ($l | unfence) end
          end
      end)
    | .out;
  def paragraphs:
    reduce (.[], "") as $l ({ps: [], cur: []};
      if ($l | test("^[ \t]*$")) then
        (if (.cur | length) > 0 then .ps[.ps | length] = (.cur | join("\n")) else . end) | .cur = []
      else .cur[.cur | length] = $l end)
    | .ps[];
  def drop_spans:
    (split("`") as $p
     | reduce $p[1:][] as $s ({t: (if $p[0] == "" then [] else [$p[0]] end), r: 0};
         .r += 1
         | if $s == "" then .
           else
             (if .r > 0 and (.t | length) > 0 and (.t[-1] | startswith("`") | not) and (.t[-1] | endswith("\\") and oddbs)
              then .t[-1] += "`" | .r -= 1 else . end)
             | (if .r > 0 then .t[.t | length] = ("`" * .r) else . end)
             | .t[.t | length] = $s | .r = 0
           end)
     | if .r > 0 then .t[.t | length] = ("`" * .r) else . end
     | .t) as $t
    | {i: 0, out: []}
    | until(.i >= ($t | length);
        $t[.i] as $x
        | if ($x | startswith("`")) then
            (first(range(.i + 1; $t | length) as $j | select($t[$j] == $x) | $j) // null) as $j
            | if $j == null then .out[.out | length] = $x | .i += 1 else .i = $j + 1 end
          else .out[.out | length] = $x | .i += 1 end)
    | .out | join("");
  (.title // "") as $title | (.body // "") as $body
  | if ($title | type) == "string" and ($body | type) == "string"
       and (($title | drop_spans | jp)
            or any($body | drop_fences | paragraphs; drop_spans | jp))
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
    L_BRANCH="ブランチ" L_RESUMED="再開元" L_RESUMED_TEXT="前回の実行" L_PROGRESS="進捗" L_TURNS="ターン数" L_ELAPSED="経過" L_REMAINING="残り"
    L_ESTIMATE="（推定）" L_LEFT_PRE=" · 残り ~" L_LEFT_POST=""
    L_TURN_ONE="1 ターン" L_TURN_MANY=" ターン"
    L_TODOS="子の todo（Issue のタスクリストではありません）" L_NO_SUBJECT="（件名なし）"
    L_MORE_1="… ほか " L_MORE_2=" 件（うち完了 " L_MORE_3=" 件）"
  else
    L_FIELD="Field" L_VALUE="Value" L_STATE="State" L_STARTED="Started" L_ENDED="Ended"
    L_BRANCH="Branch" L_RESUMED="Resumed from" L_RESUMED_TEXT="earlier run" L_PROGRESS="Progress" L_TURNS="Turns" L_ELAPSED="Elapsed" L_REMAINING="Remaining"
    L_ESTIMATE=" (estimate)" L_LEFT_PRE=" · ~" L_LEFT_POST=" left"
    L_TURN_ONE="1 turn" L_TURN_MANY=" turns"
    L_TODOS="Child's todos (not the issue's task list)" L_NO_SUBJECT="(no subject)"
    L_MORE_1="… and " L_MORE_2=" more (" L_MORE_3=" completed)"
  fi
}
state_word() {
  if [ "$LANG_CODE" = ja ]; then
    case "$1" in running) echo "実行中" ;; finished) echo "完了" ;; failed) echo "失敗" ;;
      interrupted) echo "中断" ;; incomplete) echo "未完了" ;; *) echo "$1" ;; esac
  else echo "$1"; fi
}

MAX_TODOS=50
MAX_SUBJECT=100
# clean: a todo subject as it is shown, before the code span (see TODOS
# below). The parser keeps subjects cleaned, so the state stays small however
# long the child's subjects are; the renderer cleans again, which changes
# nothing on a cleaned subject. Format characters (\p{Cf}: bidi controls,
# zero-width spaces) are dropped, so a subject cannot reorder or hide what it
# shows; control characters, line and paragraph separators, and whitespace
# runs become one space, ends trimmed; every backtick becomes '; and the
# result is cut to $max_subject characters, the last one "…". jq's gsub takes
# time quadratic in the number of matches, so a subject is first cut to 8 ×
# $max_subject characters: a huge one costs no more than that, and one that
# was cut always ends in "…", even when whitespace runs then shrink it.
# shellcheck disable=SC2016  # jq program
CLEAN='
def clean:
  (length > $max_subject * 8) as $cut
  | .[0:$max_subject * 8]
  | gsub("\\p{Cf}"; "")
  | gsub("[\\p{Cc}\\p{Zl}\\p{Zp}]"; " ") | gsub("\\s+"; " ")
  | ltrimstr(" ") | rtrimstr(" ")
  | gsub("`"; "'"'"'")
  | if $cut or length > $max_subject then .[0:$max_subject - 1] + "…" else . end;
'

# ---------------------------------------------------------------------------
# Parser: one jq process folds the whole stream and prints the state after
# every line. Lines that are not JSON, and events whose shape the step does not
# expect, are skipped rather than ending the run: if jq died, report.sh would
# exit and the child would die of SIGPIPE.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2016  # jq program: $e and $u are jq variables
PARSER="$CLEAN"'
def text_of: if type == "string" then . elif type == "array" then map(.text? // "") | join("\n") else "" end;
def step($e):
  if $e.type == "assistant" then
    (if ($e.parent_tool_use_id == null) and (($e.message.id // "") != .lastmsg)
     then .turns += 1 | .lastmsg = ($e.message.id // "") else . end)
    | reduce (($e.message.content // []) | arrays | .[]
              | select(type == "object" and .type == "tool_use" and (.id | type) == "string")) as $u (.;
        if $u.name == "TaskCreate" then .todo = true
          | .pend[$u.id] = {k: "c", j: ([$u.input | objects | .subject | strings | clean][0])}
        elif $u.name == "TaskUpdate" then .todo = true
          | .pend[$u.id] = {k: "u", t: ($u.input.taskId | tostring), s: $u.input.status,
                            j: ([$u.input | objects | .subject | strings | clean][0])}
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
            | if $id == null then . else .tasks[$id] = {status: "pending", subject: $p.j} end
          elif $p.s == "deleted" then del(.tasks[$p.t])
          elif .tasks | has($p.t) then
            (if $p.s != null then .tasks[$p.t].status = $p.s else . end)
            | (if $p.j != null then .tasks[$p.t].subject = $p.j else . end)
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
| {done: ([.tasks[] | select(.status == "completed")] | length), total: (.tasks | length),
   turns, result, tasks, pend, lastmsg, todo}
'

# ---------------------------------------------------------------------------
# The child's todo list, rendered at the end of the comment in a collapsed
# section, or nothing when there are no todos. The subjects are the child's
# text, which can carry text from whoever wrote the issue, so each one goes
# into a single inline code span, where GFM recognizes no mentions, links,
# entities, HTML, or escapes: it is cleaned (see CLEAN above: no backtick, no
# newline, at most MAX_SUBJECT characters), and an empty one gets a
# placeholder. Lines are plain bullets with a status glyph, never `- [ ]`, so
# GitHub does not count them in the issue's task progress. In creation order
# (ids compared as numbers); over MAX_TODOS lines, completed todos are hidden
# first (oldest first), then the newest pending ones, then, only when
# in-progress todos alone are over the cap, the newest in-progress ones, and a
# last bullet says how many are hidden. So the section has at most MAX_TODOS +
# 1 bullets of bounded length, and the comment stays far under GitHub's
# 65,536-character limit. An ended `failed` or `interrupted` run claims
# nothing live: its in-progress todos get the stopped glyph.
#
# precheck.sh --payload depends on this shape: the section starts at the
# body's first line that starts with `<details>`, and an in-progress line
# starts with `- 🔄`, which it turns into `- ⏸️`. Change them together.
# ---------------------------------------------------------------------------
# shellcheck disable=SC2016  # jq program
TODOS="$CLEAN"'
def neutral:
  (if type == "string" then . else "" end)
  | clean
  | if . == "" then $no_subject else . end
  | "`" + . + "`";
def glyph:
  if .status == "completed" then "✅"
  elif .status == "in_progress" then (if $st == "failed" or $st == "interrupted" then "⏸️" else "🔄" end)
  else "⬜" end;
[ (.tasks // {}) | objects | to_entries[]
  | {id: .key, n: (.key | try tonumber catch null), status: (.value.status? // null),
     subject: (.value.subject? // null)} ]
| sort_by([(.n == null), .n, .id])
| . as $all
| if length == 0 then empty
  else
    (if length <= $max_todos then {shown: $all, m: 0, k: 0}
     else (length - $max_todos) as $h
       # Hidden: the oldest completed, then the newest pending, then the
       # newest in progress, until $h are hidden.
       | [ $all[] | select(.status == "completed") | .id ] as $c
       | [ $all[] | select(.status != "completed" and .status != "in_progress") | .id ] as $p
       | [ $all[] | select(.status == "in_progress") | .id ] as $r
       | ([$h, ($c | length)] | min) as $hc
       | ([$h - $hc, ($p | length)] | min) as $hp
       | ($h - $hc - $hp) as $hr
       | def newest($n): if $n > 0 then .[length - $n:] else [] end;
         ($c[:$hc] + ($p | newest($hp)) + ($r | newest($hr))
          | map({key: ., value: true}) | from_entries) as $hidden
       | {shown: [ $all[] | select($hidden[.id] | not) ], m: $h, k: $hc}
     end)
    | "<details><summary>" + $label + "</summary>\n\n"
      + ([ .shown[] | "- " + glyph + " " + (.subject | neutral) ]
         + (if .m > 0 then ["- " + $more1 + (.m | tostring) + $more2 + (.k | tostring) + $more3] else [] end)
         | join("\n"))
      + "\n</details>"
  end
'

# todos <state> <state.json contents>: the todo section, or nothing.
todos() {
  jq -r --arg st "$1" --arg label "$L_TODOS" --arg no_subject "$L_NO_SUBJECT" \
    --arg more1 "$L_MORE_1" --arg more2 "$L_MORE_2" --arg more3 "$L_MORE_3" \
    --argjson max_todos "$MAX_TODOS" --argjson max_subject "$MAX_SUBJECT" \
    "$TODOS" <<<"$2" 2>/dev/null
}

work="$(mktemp -d "${TMPDIR:-/tmp}/jikkyo-report.XXXXXX")" || exit 1
state_file="$work/state.json"
printf '%s\n' '{"done":0,"total":0,"turns":0,"result":null}' > "$state_file"

start_ts="$(now)"

state_out=""
if common_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" \
   && [ -n "$common_dir" ]; then
  state_out="${common_dir}/jikkyo/${num}.json"
fi
comment_id=""
comment_url=""
last_write=""        # clock time of the last write
last_write_real=""   # $SECONDS at the last write, for the 1-second gap
last_key=""          # the todo list shown by the last write (CHANGE_KEY)
final_done=""
# A todo change is any change in the todo list: an id, a subject (as cleaned
# for display), or a status. So a todo moving to in progress, or renamed, is
# written at the next slot even when the completed and total counts stay the
# same. It is the list, not the rendered section: a change in a todo the cap
# hides is written too, which only costs a write at most every 30 seconds.
# `// {}` keeps the placeholder state (no .tasks) equal to the parser's empty
# list.
CHANGE_KEY='.tasks // {}'

# eta_secs <state> <done> <total> <elapsed secs>: the estimated seconds left,
# or nothing. The run-wide rate so far, applied to the todos left. Only while
# running, and only with at least one completed todo; with no rate to go on
# there is no estimate rather than a made-up time.
eta_secs() {
  local st="$1" completed="$2" total="$3" secs="$4"
  if [ "$st" = running ] && [ "$total" -gt 0 ] && [ "$completed" -gt 0 ]; then
    [ "$secs" -lt 0 ] && secs=0
    echo $((secs * (total - completed) / completed))
  fi
}

# place <temp> <dest>: rename the temp file onto <dest> without following
# <dest>. mv into a directory, or a symlink to one, moves the file inside it;
# rename(2) instead replaces a symlink itself and fails on a directory. The
# two paths differ on a <dest> that is a symlink to a directory:
# - With perl, which calls rename(2) directly, the symlink is replaced by the
#   state file.
# - Without perl (or with JIKKYO_NO_PERL=1), mv runs after a directory check,
#   so the symlink is left as it is and nothing is written. A swap between
#   the check and mv can still beat it.
# On a real directory both paths fail and write nothing.
place() {
  if [ "${JIKKYO_NO_PERL:-}" != 1 ] && command -v perl >/dev/null 2>&1; then
    perl -e 'rename($ARGV[0], $ARGV[1]) or exit 1' -- "$1" "$2"
  else
    ! [ -d "$2" ] && mv -f "$1" "$2"
  fi
}

# publish <state> <state.json contents> <end ts or empty>: write the state
# file (see the top of this file). Any failure leaves the old file and is
# otherwise ignored: the status line is a convenience, the comment is the record.
publish() {
  [ -n "$state_out" ] || return 0
  local st="$1" json="$2" end_ts="$3" t dir tmp eta comment="" completed total
  t="${end_ts:-$(now)}"
  dir="${state_out%/*}"
  read -r completed total < <(jq -r '"\(.done) \(.total)"' <<<"$json") || return 0
  eta="$(eta_secs "$st" "$completed" "$total" $((t - start_ts)))"
  [[ "$comment_id" =~ ^[1-9][0-9]*$ ]] \
    && comment="https://github.com/${owner}/${repo}/issues/${num}#issuecomment-${comment_id}"
  mkdir -p "$dir" 2>/dev/null || return 0
  # Only into a real directory. The child can write to the common dir, and a
  # jikkyo/ swapped for a symlink would have this script write wherever it
  # points, a place the child itself might not have been allowed to write.
  # This is a check, not a lock: a swap between it and mktemp still wins,
  # and puts one temp file (mode 0600, fixed-shape JSON) where the link
  # points.
  if [ ! -d "$dir" ] || [ -L "$dir" ]; then return 0; fi
  # A temp file is left behind only when this script is killed between
  # mktemp and place(); the next write of the issue takes such leftovers out.
  find "$dir" -maxdepth 1 -type f -name ".${num}.json.*" -mmin +1 -delete 2>/dev/null
  tmp="$(mktemp "${dir}/.${num}.json.XXXXXX" 2>/dev/null)" || return 0
  if jq -c -n --argjson s "$json" --arg st "$st" --arg lang "$LANG_CODE" --arg session "$session" \
       --arg issue "https://github.com/${owner}/${repo}/issues/${num}" --arg comment "$comment" \
       --argjson number "$num" --argjson started "$start_ts" --argjson updated "$t" \
       --arg eta "$eta" \
       '{v: 1, issue: $issue, number: $number, state: $st, done: $s.done, total: $s.total,
         turns: $s.turns, started: $started, updated: $updated,
         eta_secs: (if $eta == "" then null else ($eta | tonumber) end), lang: $lang,
         session: (if $session == "" then null else $session end),
         comment: (if $comment == "" then null else $comment end)}' > "$tmp" 2>/dev/null \
     && place "$tmp" "$state_out" 2>/dev/null; then
    return 0
  fi
  rm -f "$tmp"
}

# body <state> <state.json contents> <end ts or empty>
body() {
  local st="$1" json="$2" end_ts="$3" t completed total turns heading label value ended elapsed
  local secs eta="" eta_cell="" eta_suffix="" word section
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
  eta="$(eta_secs "$st" "$completed" "$total" "$secs")"
  if [ -n "$eta" ]; then
    eta="$(fmt_duration "$eta")"
    eta_cell="~${eta}${L_ESTIMATE}"
    eta_suffix="${L_LEFT_PRE}${eta}${L_LEFT_POST}"
  fi
  word="$(state_word "$st")"
  if [ -n "$branch" ]; then
    printf '<!-- jikkyo:status v=1 state=%s branch=%s -->\n' "$st" "$branch"
  else
    printf '<!-- jikkyo:status v=1 state=%s -->\n' "$st"
  fi
  printf '### jikkyo · %s · %s%s\n\n' "$word" "$heading" "$eta_suffix"
  printf '| %s | %s |\n| --- | --- |\n' "$L_FIELD" "$L_VALUE"
  printf '| %s | %s |\n' "$L_STATE" "$word"
  printf '| %s | %s |\n' "$L_BRANCH" "${branch:+\`$branch\`}"
  if [ -n "$resumed_from" ]; then
    printf '| %s | [%s](https://github.com/%s/%s/issues/%s#issuecomment-%s) |\n' \
      "$L_RESUMED" "$L_RESUMED_TEXT" "$owner" "$repo" "$num" "$resumed_from"
  fi
  printf '| %s | %s |\n' "$L_STARTED" "$(fmt_time "$start_ts")"
  printf '| %s | %s |\n' "$L_ENDED" "$ended"
  printf '| %s | %s |\n' "$label" "$value"
  printf '| %s | %s |\n' "$L_ELAPSED" "$elapsed"
  printf '| %s | %s |\n' "$L_REMAINING" "$eta_cell"
  # The todo section goes last: precheck.sh --payload rewrites only what comes
  # before its first `<details>` line, the part jikkyo alone writes.
  section="$(todos "$st" "$json")"
  [ -n "$section" ] && printf '\n%s\n' "$section"
  return 0
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
  # The body goes to jq on a pipe, not as an argument, so no size limit on a
  # single argument applies. It ends with exactly one newline, which is dropped.
  payload="$(body "$st" "$json" "$end_ts" | jq -Rs '{body: rtrimstr("\n")}')"
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
  publish "$st" "$json" "$end_ts"
  last_write="$(now)"
  last_write_real="$SECONDS"
  last_key="$(jq -c "$CHANGE_KEY" <<<"$json")"
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
  jq -r '.result as $r
         | if $r == null then "interrupted"
           elif $r.is_error == true or $r.subtype != "success" then "failed"
           elif .done < .total then "incomplete"
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
  jq -R -n -c --unbuffered --argjson max_subject "$MAX_SUBJECT" "$PARSER" | while IFS= read -r s; do
    printf '%s\n' "$s" > "$state_file.tmp" && mv "$state_file.tmp" "$state_file"
  done
  : > "$work/eof"
) <&3 &
parser_pid=$!

while [ ! -e "$work/eof" ]; do
  sleep "$TICK"
  [ -e "$work/eof" ] && break
  t="$(now)"
  key="$(jq -c "$CHANGE_KEY" "$state_file" 2>/dev/null)" || continue
  if [ "$key" != "$last_key" ] && [ $((t - last_write)) -ge "$TODO_INTERVAL" ]; then
    write running
  elif [ $((t - last_write)) -ge "$HEARTBEAT_INTERVAL" ]; then
    write running
  fi
done
wait "$parser_pid" 2>/dev/null
parser_pid=""

finish "$(final_state)"
