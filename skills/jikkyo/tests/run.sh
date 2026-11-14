#!/usr/bin/env bash
#
# run.sh — regression tests for the jikkyo scripts.
#
# Dependencies: bash, git, jq. `gh` and `claude` are replaced by stubs on PATH,
# so nothing here touches GitHub or starts a model. Run from anywhere:
#
#   bash skills/jikkyo/tests/run.sh
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS="$(cd "${HERE}/../scripts" && pwd)"
REPORT="${SCRIPTS}/report.sh"
LAUNCH="${SCRIPTS}/launch.sh"
PRECHECK="${SCRIPTS}/precheck.sh"
CLEANUP="${SCRIPTS}/cleanup.sh"
SKILL_MD="${HERE}/../SKILL.md"
URL="https://github.com/o/r/issues/12"

pass=0
fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail + 1)); }

# assert_eq <label> <expected> <actual>
assert_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (expected [$2], got [$3])"; fi
}
# assert_has <label> <needle> <haystack>
assert_has() {
  case "$3" in *"$2"*) ok "$1" ;; *) bad "$1 (missing [$2] in [$3])" ;; esac
}
# assert_lacks <label> <needle> <haystack>
assert_lacks() {
  case "$3" in *"$2"*) bad "$1 (unexpected [$2] in [$3])" ;; *) ok "$1" ;; esac
}

TMP="$(mktemp -d "${TMPDIR:-/tmp}/jikkyo-tests.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# --- stubs -----------------------------------------------------------------
# gh: every call is logged as $GH_LOG/<n>.args and $GH_LOG/<n>.body (stdin).
# A POST answers with a comment id and URL, the way `--jq '[.id,.html_url]|@tsv'`
# would.
STUBS="$TMP/stubs"
mkdir -p "$STUBS"
# The read of the issue (`gh api repos/o/r/issues/12`, for the language) is
# logged apart, in $GH_LOG/reads, and answers with $GH_ISSUE (an English issue
# when unset), so the write counts below stay the writes alone.
cat > "$STUBS/gh" <<'EOF'
#!/usr/bin/env bash
if [ "$*" = "api repos/o/r/issues/12" ]; then
  printf '%s\n' "$*" >> "$GH_LOG/reads"
  if [ -n "${GH_ISSUE:-}" ]; then cat "$GH_ISSUE"; else echo '{"title":"An issue","body":"In English."}'; fi
  exit "${GH_ISSUE_RC:-0}"
fi
n=$(( $(cat "$GH_LOG/count" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$GH_LOG/count"
printf '%s\n' "$*" > "$GH_LOG/$n.args"
cat > "$GH_LOG/$n.body"
case "$*" in *"-X POST"*) printf '777\thttps://github.com/o/r/issues/12#issuecomment-777\n' ;; esac
exit 0
EOF
# claude: records its arguments (one per line) and the todo-tools variable,
# says on stderr that it started, then replays $CLAUDE_STREAM as its stream.
cat > "$STUBS/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$CLAUDE_ARGS"
printf '%s\n' "${CLAUDE_CODE_ENABLE_TODO_TOOLS:-unset}" > "$CLAUDE_ARGS.env"
cat > "$CLAUDE_ARGS.stdin"
echo "child-started" >&2
cat "$CLAUDE_STREAM"
EOF
chmod +x "$STUBS/gh" "$STUBS/claude"
export PATH="$STUBS:$PATH"

export JIKKYO_TICK=0.1 JIKKYO_MIN_GAP=0

new_log() { GH_LOG="$(mktemp -d "$TMP/gh.XXXXXX")"; export GH_LOG; }
calls() { cat "$GH_LOG/count" 2>/dev/null || echo 0; }
nth_body() { jq -r '.body' "$GH_LOG/$1.body"; }
last_body() { nth_body "$(calls)"; }
heading() { printf '%s\n' "$1" | sed -n '2p'; }
marker_state() { printf '%s\n' "$1" | sed -n '1s/.*state=\([a-z]*\).*/\1/p'; }

# --- stream fixtures -------------------------------------------------------
msg=0
assistant_tool() {  # <tool_use id> <name> <input json> [parent id]
  msg=$((msg + 1))
  jq -cn --arg id "$1" --arg name "$2" --argjson input "$3" --arg m "msg_$msg" --arg parent "${4:-}" \
    '{type: "assistant", parent_tool_use_id: (if $parent == "" then null else $parent end),
      message: {id: $m, content: [{type: "tool_use", id: $id, name: $name, input: $input}]}}'
}
assistant_text() {  # [parent id]
  msg=$((msg + 1))
  jq -cn --arg m "msg_$msg" --arg parent "${1:-}" \
    '{type: "assistant", parent_tool_use_id: (if $parent == "" then null else $parent end),
      message: {id: $m, content: [{type: "text", text: "working"}]}}'
}
tool_result() {  # <tool_use id> <content> [is_error]
  jq -cn --arg id "$1" --arg c "$2" --argjson err "${3:-false}" \
    '{type: "user", message: {content: [{type: "tool_result", tool_use_id: $id, content: $c, is_error: $err}]}}'
}
create() {  # <tool_use id> <task id>
  assistant_tool "$1" TaskCreate '{"subject":"s","description":"d"}'
  tool_result "$1" "Task #$2 created successfully: s"
}
update() {  # <tool_use id> <task id> <status>
  assistant_tool "$1" TaskUpdate "$(jq -cn --arg t "$2" --arg s "$3" '{taskId: $t, status: $s}')"
  tool_result "$1" "Updated task #$2 status"
}
result_ok() { jq -cn '{type: "result", subtype: "success", is_error: false, num_turns: 3, result: "All done. Opened PR #99."}'; }
result_err() { jq -cn --arg st "$1" '{type: "result", subtype: $st, is_error: true, errors: ["Reached maximum number of turns", "second error"]}'; }

run_report() {  # <stream file> -> stdout in $TMP/out, exit code in $rc
  new_log
  rc=0
  bash "$REPORT" "$URL" < "$1" > "$TMP/out" 2> "$TMP/err" || rc=$?
}

# ===========================================================================
echo "report.sh: progress"
{
  f="$TMP/progress.jsonl"
  {
    create t1 1; create t2 2; create t3 3
    update u1 1 in_progress; update u2 1 completed
    update u3 2 deleted
    create t4 4          # added mid-run: 1/3 -> still 1/3 after the delete
    update u4 3 completed
    result_ok
  } > "$f"
  run_report "$f"
  b="$(last_body)"
  assert_eq "completed / non-deleted tasks, with a deletion and a mid-run add" "### jikkyo · finished · 66%" "$(heading "$b")"
  assert_has "the table carries the progress row" "| Progress | 66% |" "$b"

  # The % can go down when the child adds tasks.
  f="$TMP/down-before.jsonl"
  { create a 1; create b 2; create c 3; create d 4
    update e 1 completed; update f 2 completed; update g 3 completed; } > "$f"
  run_report "$f"
  assert_eq "before the add: 3 of 4 todos" "### jikkyo · interrupted · 75%" "$(heading "$(last_body)")"
  f="$TMP/down.jsonl"
  { cat "$TMP/down-before.jsonl"; create h 5; create i 6; } > "$f"
  run_report "$f"
  b="$(last_body)"
  assert_eq "progress drops when tasks are added (3/4 -> 3/6)" "### jikkyo · interrupted · 50%" "$(heading "$b")"
  assert_has "the Progress row drops too" "| Progress | 50% |" "$b"

  # A TaskCreate whose result is an error creates nothing; neither does an
  # update to a task that was never created.
  f="$TMP/errors.jsonl"
  { create a 1
    assistant_tool b TaskCreate '{"subject":"x","description":"y"}'; tool_result b "boom" true
    update c 9 completed; update d 1 completed; result_ok; } > "$f"
  run_report "$f"
  assert_eq "failed creates and unknown task ids are ignored" "### jikkyo · finished · 100%" "$(heading "$(last_body)")"

  # The task id can also come from the structured tool_use_result.
  f="$TMP/structured.jsonl"
  { assistant_tool s1 TaskCreate '{"subject":"x","description":"y"}'
    jq -cn '{type: "user", tool_use_result: {task: {id: "5"}},
             message: {content: [{type: "tool_result", tool_use_id: "s1", content: [{type: "text", text: "ok"}]}]}}'
    update s2 5 completed; result_ok; } > "$f"
  run_report "$f"
  assert_eq "task id read from tool_use_result when the text has none" "### jikkyo · finished · 100%" "$(heading "$(last_body)")"

  # No todo events: turn count, no %.
  f="$TMP/notodo.jsonl"
  { assistant_text; assistant_tool x Bash '{"command":"ls"}'; tool_result x "a b"
    assistant_text parent_1      # a subagent's message is not a turn
    assistant_text; result_ok; } > "$f"
  run_report "$f"
  b="$(last_body)"
  assert_eq "no todos: the heading shows the turn count" "### jikkyo · finished · 3 turns" "$(heading "$b")"
  assert_has "no todos: the table shows the turn count" "| Turns | 3 |" "$b"
  assert_lacks "no todos: no % anywhere" "%" "$b"

  # Events whose shape the parser does not expect are skipped, not fatal: a jq
  # error would end report.sh and kill the child with SIGPIPE.
  f="$TMP/shapes.jsonl"
  { create a 1
    echo '{"type":"assistant","message":{"id":"m","content":"a string"}}'
    echo '{"type":"user","message":{"content":"a string"}}'
    echo '{"type":"assistant","message":{"id":"m2","content":[{"type":"tool_use","name":"TaskCreate","input":{}}]}}'
    echo '{"type":"user","message":{"content":[{"type":"tool_result","content":"Task #7 created"}]}}'
    assistant_tool z TaskCreate '{"subject":"x","description":"y"}'
    jq -cn '{type: "user", tool_use_result: "a string",
             message: {content: [{type: "tool_result", tool_use_id: "z", content: "no id here"}]}}'
    echo '{"type":"user","message":{"content":[42, null, "x"]}}'
    update b 1 completed; result_ok; } > "$f"
  run_report "$f"
  assert_eq "unexpected event shapes are skipped and the run goes on" "### jikkyo · finished · 100%" "$(heading "$(last_body)")"
  assert_has "...and the final message still arrives" "All done. Opened PR #99." "$(cat "$TMP/out")"

  # Garbage lines do not end the run.
  f="$TMP/garbage.jsonl"
  { echo 'not json'; echo '[1,2]'; create a 1; update b 1 completed; result_ok; } > "$f"
  run_report "$f"
  assert_eq "lines that are not JSON objects are skipped" "### jikkyo · finished · 100%" "$(heading "$(last_body)")"
}

# ===========================================================================
echo "report.sh: end states and the final message"
{
  f="$TMP/ok.jsonl"; { create a 1; result_ok; } > "$f"
  run_report "$f"
  b="$(last_body)"
  assert_eq "a success result gives finished" "finished" "$(marker_state "$b")"
  assert_has "finished: the table says so" "| State | finished |" "$b"
  if printf '%s\n' "$b" | grep -Eq '^\| Ended \| [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} [+-][0-9]{4} \|$'; then
    ok "the end time is local time with a UTC offset"
  else bad "the end time is local time with a UTC offset ($b)"; fi
  if printf '%s\n' "$b" | grep -Eq '^\| Started \| [0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2} [+-][0-9]{4} \|$'; then
    ok "the start time is local time with a UTC offset"
  else bad "the start time is local time with a UTC offset ($b)"; fi
  assert_has "elapsed time is shown" "| Elapsed | " "$b"
  out="$(cat "$TMP/out")"
  assert_has "success: prints the result text" "$(printf 'jikkyo: final message:\nAll done. Opened PR #99.')" "$out"
  assert_has "prints the status comment URL" "jikkyo: status comment https://github.com/o/r/issues/12#issuecomment-777" "$out"
  assert_has "prints the final state" "jikkyo: state finished" "$out"
  assert_eq "exits 0 at the end of the stream" "0" "$rc"

  f="$TMP/maxturns.jsonl"; { create a 1; result_err error_max_turns; } > "$f"
  run_report "$f"
  assert_eq "subtype error_max_turns gives failed" "failed" "$(marker_state "$(last_body)")"
  assert_has "error_*: prints the errors" "$(printf 'jikkyo: final message:\nReached maximum number of turns\nsecond error')" "$(cat "$TMP/out")"

  f="$TMP/exec.jsonl"; result_err error_during_execution > "$f"
  run_report "$f"
  assert_eq "subtype error_during_execution gives failed" "failed" "$(marker_state "$(last_body)")"

  f="$TMP/iserror.jsonl"
  jq -cn '{type: "result", subtype: "success", is_error: true, result: "API error"}' > "$f"
  run_report "$f"
  assert_eq "is_error true gives failed even with subtype success" "failed" "$(marker_state "$(last_body)")"

  f="$TMP/noresult.jsonl"; { create a 1; update b 1 completed; } > "$f"
  run_report "$f"
  assert_eq "no result line gives interrupted" "interrupted" "$(marker_state "$(last_body)")"
  out="$(cat "$TMP/out")"
  assert_has "no result line: says there is no final message" "jikkyo: no final message" "$out"
  assert_lacks "no result line: prints no final message" "final message:" "$out"

  f="$TMP/emptyresult.jsonl"
  jq -cn '{type: "result", subtype: "success", is_error: false, result: ""}' > "$f"
  run_report "$f"
  out="$(cat "$TMP/out")"
  assert_has "an empty result text: says the final message is empty" "jikkyo: final message is empty" "$out"
  assert_lacks "an empty result text: no bare final-message header" "final message:" "$out"

  : > "$TMP/empty.jsonl"
  run_report "$TMP/empty.jsonl"
  assert_eq "an empty stream still gets a start and an end write" "2" "$(calls)"
  assert_eq "an empty stream ends interrupted" "interrupted" "$(marker_state "$(last_body)")"
}

# ===========================================================================
echo "report.sh: where it writes"
{
  f="$TMP/where.jsonl"; { create a 1; result_ok; } > "$f"
  run_report "$f"
  assert_eq "the first write creates a comment on the issue" \
    "api -X POST repos/o/r/issues/12/comments --input - --jq [.id, .html_url] | @tsv" "$(cat "$GH_LOG/1.args")"
  assert_eq "later writes PATCH that comment by id" \
    "api -X PATCH repos/o/r/issues/comments/777 --input -" "$(cat "$GH_LOG/$(calls).args")"
  all="$(cat "$GH_LOG"/*.args)"
  assert_lacks "never uses --edit-last" "edit-last" "$all"
  assert_lacks "never edits the issue body" "issues/12 " "$all"
  assert_eq "the marker is the first line of the body" "<!-- jikkyo:status v=1 state=running -->" "$(nth_body 1 | head -n 1)"
  assert_eq "a running comment has an empty end time" "| Ended |  |" "$(nth_body 1 | grep '^| Ended')"

  # A failed create is retried at the next write instead of PATCHing nothing.
  new_log
  cat > "$TMP/gh-fail" <<'EOF'
#!/usr/bin/env bash
[ "$*" = "api repos/o/r/issues/12" ] && { echo '{"title":"t","body":"b"}'; exit 0; }
n=$(( $(cat "$GH_LOG/count" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$GH_LOG/count"
printf '%s\n' "$*" > "$GH_LOG/$n.args"; cat > "$GH_LOG/$n.body"
[ "$n" -eq 1 ] && exit 1
case "$*" in *"-X POST"*) printf '888\thttps://github.com/o/r/issues/12#issuecomment-888\n' ;; esac
EOF
  mkdir -p "$TMP/stubs-fail"; cp "$TMP/gh-fail" "$TMP/stubs-fail/gh"; chmod +x "$TMP/stubs-fail/gh"
  PATH="$TMP/stubs-fail:$PATH" bash "$REPORT" "$URL" < "$f" > "$TMP/out" 2>/dev/null
  assert_eq "a failed create is retried as a create" "api -X POST repos/o/r/issues/12/comments --input - --jq [.id, .html_url] | @tsv" "$(cat "$GH_LOG/2.args")"

  rc=0; bash "$REPORT" "https://example.com/x" < /dev/null >/dev/null 2>&1 || rc=$?
  assert_eq "a non-issue URL is a usage error" "2" "$rc"
}

# ===========================================================================
echo "report.sh: the branch"
{
  BR="worktree-jikkyo-12-20261114-132452"
  f="$TMP/branch.jsonl"; { create a 1; result_ok; } > "$f"
  new_log
  rc=0; bash "$REPORT" "$URL" "$BR" < "$f" > "$TMP/out" 2> "$TMP/err" || rc=$?
  assert_eq "with a branch: exits 0" "0" "$rc"
  assert_eq "the first write's marker carries branch= after state=" \
    "<!-- jikkyo:status v=1 state=running branch=$BR -->" "$(nth_body 1 | head -n 1)"
  BR_RUNNING_BODY="$(nth_body 1)"   # a running comment with a branch, for the precheck tests
  b="$(last_body)"
  assert_eq "the final write's marker keeps branch=" \
    "<!-- jikkyo:status v=1 state=finished branch=$BR -->" "$(printf '%s\n' "$b" | head -n 1)"
  assert_eq "marker_state still reads the state" "finished" "$(marker_state "$b")"
  # shellcheck disable=SC2016  # literal backticks around the branch
  assert_eq "the table has a Branch row right after State" \
    "$(printf '| State | finished |\n| Branch | `%s` |' "$BR")" "$(printf '%s\n' "$b" | sed -n '6,7p')"

  # Without a branch (older callers): no branch= field, and an empty row.
  run_report "$f"
  b="$(last_body)"
  assert_eq "without a branch the marker has no branch= field" \
    "<!-- jikkyo:status v=1 state=finished -->" "$(printf '%s\n' "$b" | head -n 1)"
  assert_eq "without a branch the Branch row is empty" "| Branch |  |" "$(printf '%s\n' "$b" | grep '^| Branch')"

  # Only the exact shape for this issue's number is written; anything else
  # is a usage error before the first write.
  # shellcheck disable=SC2016  # a literal $(id), never expanded
  for bad_branch in "" "worktree-jikkyo-13-20261114-132452" "worktree-jikkyo-12-2026111-132452" \
      "worktree-jikkyo-12-20261114-1324520" "jikkyo-12-20261114-132452" "main" \
      "worktree-jikkyo-12-20261114-132452 -->" "worktree-jikkyo-12-20261114-132452
x" "worktree-jikkyo-12-20261114-13245a" "worktree-jikkyo-012-20261114-132452" \
      'worktree-jikkyo-12-20261114-132452$(id)'; do
    new_log
    rc=0; bash "$REPORT" "$URL" "$bad_branch" < "$f" >/dev/null 2>&1 || rc=$?
    if [ "$rc" = 2 ] && [ "$(calls)" = 0 ]; then ok "rejects branch [$bad_branch] without writing"
    else bad "rejects branch [$bad_branch] without writing (rc=$rc, calls=$(calls))"; fi
  done
  new_log
  rc=0; bash "$REPORT" "$URL" "$BR" extra < "$f" >/dev/null 2>&1 || rc=$?
  assert_eq "a third argument is a usage error" "2:0" "$rc:$(calls)"

  # In Japanese: the same marker, a Japanese label.
  jq -cn '{title: "日本語", body: ""}' > "$TMP/issue-br.json"
  new_log
  GH_ISSUE="$TMP/issue-br.json" bash "$REPORT" "$URL" "$BR" < "$f" > "$TMP/out" 2>&1
  BR_RUNNING_BODY_JA="$(nth_body 1)"
  b="$(last_body)"
  assert_eq "Japanese: the marker carries the same branch= field" \
    "<!-- jikkyo:status v=1 state=finished branch=$BR -->" "$(printf '%s\n' "$b" | head -n 1)"
  # shellcheck disable=SC2016  # literal backticks around the branch
  assert_eq "Japanese: the Branch row is labelled ブランチ" \
    "$(printf '| 状態 | 完了 |\n| ブランチ | `%s` |' "$BR")" "$(printf '%s\n' "$b" | sed -n '6,7p')"
  assert_lacks "Japanese: no English Branch label" "| Branch |" "$b"
}

# ===========================================================================
echo "report.sh: the language of the issue"
{
  issue() { jq -cn --arg t "$1" --arg b "$2" '{title: $t, body: $b}' > "$TMP/issue.json"; }
  f="$TMP/lang.jsonl"; { create a 1; create b 2; update c 1 completed; result_ok; } > "$f"

  # English, as today.
  issue "Fix the parser" "It breaks on a blank line."
  GH_ISSUE="$TMP/issue.json" run_report "$f"
  b="$(last_body)"
  assert_has "English issue: prints the language" "jikkyo: language en" "$(cat "$TMP/out")"
  assert_eq "English issue: the heading is English" "### jikkyo · finished · 50%" "$(heading "$b")"
  assert_eq "English issue: the field names are English" \
    "| Field | Value |,| State | finished |,| Progress | 50% |" \
    "$(printf '%s\n' "$b" | grep -E '^\| (Field|State|Progress) ' | paste -sd, -)"
  assert_eq "the issue is read once, with a plain GET" "api repos/o/r/issues/12" "$(cat "$GH_LOG/reads")"

  # Japanese in the body, with the issue's own text in it.
  issue "Parser bug" "空行で落ちます。\$(touch $TMP/pwned) SECRET-ISSUE-TEXT"
  GH_ISSUE="$TMP/issue.json" run_report "$f"
  b="$(last_body)"
  assert_has "Japanese issue: prints the language" "jikkyo: language ja" "$(cat "$TMP/out")"
  assert_eq "Japanese issue: the marker keeps v=1 and the English state" \
    "<!-- jikkyo:status v=1 state=finished -->" "$(printf '%s\n' "$b" | head -n 1)"
  assert_eq "Japanese issue: the heading is Japanese" "### jikkyo · 完了 · 50%" "$(heading "$b")"
  want="$(printf '%s\n' '| 項目 | 値 |' '| --- | --- |' '| 状態 | 完了 |')"
  assert_eq "Japanese issue: the table header and State row are Japanese" "$want" "$(printf '%s\n' "$b" | sed -n '4,6p')"
  for row in '| 開始 | 2' '| 終了 | 2' '| 進捗 | 50% |' '| 経過 | ' '| 残り |  |'; do
    assert_has "Japanese issue: row [$row]" "$row" "$b"
  done
  for word in Field State Started Ended Progress Elapsed Remaining finished; do
    assert_lacks "Japanese issue: no English [$word] in the visible text" "$word" "$(printf '%s\n' "$b" | sed '1d')"
  done
  all="$(cat "$GH_LOG"/*.args "$GH_LOG"/*.body)"
  assert_lacks "no text from the issue reaches the comment or a command line" "SECRET-ISSUE-TEXT" "$all$(cat "$TMP/out" "$TMP/err")"
  assert_lacks "...not even the Japanese part" "空行" "$all"
  if [ -e "$TMP/pwned" ]; then bad "the issue's text is never run"; else ok "the issue's text is never run"; fi

  # Only the title in Japanese; katakana alone; halfwidth katakana.
  issue "パーサの不具合" "It breaks."
  GH_ISSUE="$TMP/issue.json" run_report "$f"
  assert_eq "Japanese in the title alone gives ja" "### jikkyo · 完了 · 50%" "$(heading "$(last_body)")"
  issue "x" "ｴﾗｰ"
  GH_ISSUE="$TMP/issue.json" run_report "$f"
  assert_has "halfwidth katakana gives ja" "jikkyo: language ja" "$(cat "$TMP/out")"
  issue "Café — naïve «quotes» ü" "Ünïcödé, but not Japanese: 한국어"
  GH_ISSUE="$TMP/issue.json" run_report "$f"
  assert_has "other non-ASCII text gives en" "jikkyo: language en" "$(cat "$TMP/out")"

  # A failed read, or an answer that is not an issue, falls back to English.
  echo '{"message":"Not Found"}' > "$TMP/issue.json"
  GH_ISSUE="$TMP/issue.json" GH_ISSUE_RC=1 run_report "$f"
  assert_eq "a failed issue read gives en" "### jikkyo · finished · 50%" "$(heading "$(last_body)")"
  echo 'not json' > "$TMP/issue.json"
  GH_ISSUE="$TMP/issue.json" run_report "$f"
  assert_has "an answer that is not JSON gives en" "jikkyo: language en" "$(cat "$TMP/out")"
  jq -cn '{title: null, body: null}' > "$TMP/issue.json"
  GH_ISSUE="$TMP/issue.json" run_report "$f"
  assert_has "an issue with no title or body gives en" "jikkyo: language en" "$(cat "$TMP/out")"

  # The other states and the turn count, in Japanese.
  issue "日本語" ""
  export GH_ISSUE="$TMP/issue.json"
  f="$TMP/lang-fail.jsonl"; { create a 1; result_err error_max_turns; } > "$f"
  run_report "$f"
  b="$(last_body)"
  assert_eq "Japanese: failed" "### jikkyo · 失敗 · 0%" "$(heading "$b")"
  assert_eq "Japanese: failed keeps the English marker" "failed" "$(marker_state "$b")"
  f="$TMP/lang-int.jsonl"; { assistant_text; assistant_text; } > "$f"
  run_report "$f"
  b="$(last_body)"
  assert_eq "Japanese: interrupted, with the turn count" "### jikkyo · 中断 · 2 ターン" "$(heading "$b")"
  assert_has "Japanese: the Turns row" "| ターン数 | 2 |" "$b"
  f="$TMP/lang-one.jsonl"; { assistant_text; result_ok; } > "$f"
  run_report "$f"
  assert_eq "Japanese: one turn" "### jikkyo · 完了 · 1 ターン" "$(heading "$(last_body)")"
  assert_eq "Japanese: the first write says running" "### jikkyo · 実行中 · 0 ターン" "$(heading "$(nth_body 1)")"
  assert_eq "Japanese: running keeps the English marker" "running" "$(marker_state "$(nth_body 1)")"
  assert_has "the final message is passed on unchanged" "All done. Opened PR #99." "$(cat "$TMP/out")"
  assert_has "the hand-over state stays English" "jikkyo: state finished" "$(cat "$TMP/out")"
  unset GH_ISSUE
}

# ===========================================================================
# Timing runs against a fake clock: the test owns "now" and feeds the stream
# through a FIFO, so it can hold the stream open while the clock moves.
echo "report.sh: when it writes"
{
  new_log
  clock="$TMP/clock"; echo 1000 > "$clock"
  fifo="$TMP/fifo"; rm -f "$fifo"; mkfifo "$fifo"
  JIKKYO_CLOCK_FILE="$clock" bash "$REPORT" "$URL" < "$fifo" > "$TMP/out" 2>&1 &
  rpid=$!
  exec 4> "$fifo"
  at() { echo "$1" > "$clock"; }
  settle() { sleep 0.6; }

  settle
  assert_eq "start: written at once, before any event" "1" "$(calls)"

  at 1005; create t1 1 >&4; settle
  assert_eq "a todo change inside the 30 s window is held" "1" "$(calls)"
  at 1029; settle
  assert_eq "still held at 29 s" "1" "$(calls)"
  at 1030; settle
  assert_eq "the held change is written at the next slot (30 s)" "2" "$(calls)"
  assert_eq "the held write shows the change" "### jikkyo · running · 0%" "$(heading "$(last_body)")"

  at 1031; update u1 1 in_progress >&4; update u2 1 completed >&4; settle
  at 1059; settle
  assert_eq "back-to-back changes are coalesced and held" "2" "$(calls)"
  at 1060; settle
  assert_eq "they are written as one write" "3" "$(calls)"
  assert_eq "that write shows the latest state" "### jikkyo · running · 100% · ~0s left" "$(heading "$(last_body)")"

  at 1200; settle
  assert_eq "no change, no write before the heartbeat" "3" "$(calls)"
  at 1359; settle
  assert_eq "no heartbeat at 4 m 59 s" "3" "$(calls)"
  at 1360; settle
  assert_eq "a heartbeat after 5 minutes without a change" "4" "$(calls)"
  assert_has "the heartbeat refreshes the elapsed time" "| Elapsed | 6m 00s |" "$(last_body)"

  at 1361; create t2 2 >&4; settle
  assert_eq "a change right after the heartbeat is held" "4" "$(calls)"
  exec 4>&-
  wait "$rpid"
  assert_eq "end: written at once when the stream ends" "5" "$(calls)"
  assert_eq "the pending change is in the end write" "### jikkyo · interrupted · 50%" "$(heading "$(last_body)")"
  rm -f "$fifo"
}

# ===========================================================================
echo "report.sh: estimated time remaining"
{
  remaining() { printf '%s\n' "$1" | grep '^| Remaining'; }
  new_log
  clock="$TMP/clock"; echo 1000 > "$clock"
  fifo="$TMP/fifo-eta"; rm -f "$fifo"; mkfifo "$fifo"
  JIKKYO_CLOCK_FILE="$clock" bash "$REPORT" "$URL" < "$fifo" > "$TMP/out" 2>&1 &
  rpid=$!
  exec 4> "$fifo"
  settle() { sleep 0.6; }

  settle
  b="$(last_body)"
  assert_eq "no todos: the Remaining row is empty" "| Remaining |  |" "$(remaining "$b")"
  assert_eq "no todos: no estimate in the heading" "### jikkyo · running · 0 turns" "$(heading "$b")"

  { create t1 1; create t2 2; create t3 3; create t4 4; } >&4
  echo 1060 > "$clock"; settle
  assert_eq "todos written" "2" "$(calls)"
  b="$(last_body)"
  assert_eq "none completed: the Remaining row is empty" "| Remaining |  |" "$(remaining "$b")"
  assert_eq "none completed: no estimate in the heading" "### jikkyo · running · 0%" "$(heading "$b")"

  # 150 s for 1 of 4 todos: 150 / 1 * 3 = 450 s left.
  update u1 1 completed >&4
  echo 1150 > "$clock"; settle
  assert_eq "progress written" "3" "$(calls)"
  b="$(last_body)"
  assert_eq "partial progress: the Remaining row has the estimate" \
    "| Remaining | ~7m 30s (estimate) |" "$(remaining "$b")"
  assert_eq "partial progress: the heading carries the estimate" \
    "### jikkyo · running · 25% · ~7m 30s left" "$(heading "$b")"

  result_ok >&4
  exec 4>&-
  wait "$rpid"
  b="$(last_body)"
  assert_eq "finished: the Remaining row is empty" "| Remaining |  |" "$(remaining "$b")"
  assert_eq "finished: no estimate in the heading" "### jikkyo · finished · 25%" "$(heading "$b")"
  rm -f "$fifo"

  # The same estimate in Japanese: the words change, the duration format not.
  jq -cn '{title: "見積もり", body: ""}' > "$TMP/issue-ja.json"
  new_log
  echo 1000 > "$clock"
  fifo="$TMP/fifo-eta-ja"; rm -f "$fifo"; mkfifo "$fifo"
  GH_ISSUE="$TMP/issue-ja.json" JIKKYO_CLOCK_FILE="$clock" bash "$REPORT" "$URL" < "$fifo" > "$TMP/out" 2>&1 &
  rpid=$!
  exec 4> "$fifo"
  settle   # the start write, at 1000
  { create t1 1; create t2 2; create t3 3; create t4 4; update u1 1 completed; } >&4
  echo 1150 > "$clock"; settle
  b="$(last_body)"
  assert_eq "Japanese: the Remaining row has the estimate" "| 残り | ~7m 30s（推定） |" "$(printf '%s\n' "$b" | grep '^| 残り')"
  assert_eq "Japanese: the heading carries the estimate" "### jikkyo · 実行中 · 25% · 残り ~7m 30s" "$(heading "$b")"
  JA_ETA_BODY="$b"   # a running Japanese comment, for the precheck tests
  exec 4>&-
  wait "$rpid"
  assert_eq "Japanese, ended: no estimate in the heading" "### jikkyo · 中断 · 25%" "$(heading "$(last_body)")"
  assert_eq "Japanese, ended: the Remaining row is empty" "| 残り |  |" "$(last_body | grep '^| 残り')"
  rm -f "$fifo"
}

# ===========================================================================
echo "report.sh: signals"
{
  for sig in TERM HUP INT; do
    new_log
    fifo="$TMP/fifo-$sig"; mkfifo "$fifo"
    # Job control on, so the background report.sh does not inherit an ignored
    # SIGINT (asynchronous commands ignore it otherwise).
    set -m
    bash "$REPORT" "$URL" < "$fifo" > "$TMP/out-$sig" 2>&1 &
    rpid=$!
    set +m
    exec 4> "$fifo"
    create t1 1 >&4
    sleep 0.6
    kill -s "$sig" "$rpid"
    rc=0; wait "$rpid" || rc=$?
    exec 4>&-
    assert_eq "SIG$sig writes interrupted before exiting" "interrupted" "$(marker_state "$(last_body)")"
    assert_has "SIG$sig: the end time is written" "| Ended | 2" "$(last_body)"
    case "$sig" in TERM) want=143 ;; HUP) want=129 ;; INT) want=130 ;; esac
    assert_eq "SIG$sig: exits $want" "$want" "$rc"
    assert_has "SIG$sig: says there is no final message" "jikkyo: no final message" "$(cat "$TMP/out-$sig")"
    rm -f "$fifo"
  done
}

# ===========================================================================
echo "report.sh: a signal after the result line"
{
  new_log
  fifo="$TMP/fifo-late"; mkfifo "$fifo"
  bash "$REPORT" "$URL" < "$fifo" > "$TMP/out-late" 2>&1 &
  rpid=$!
  exec 4> "$fifo"
  { create t1 1; result_ok; } >&4
  sleep 0.6
  kill -s TERM "$rpid"
  rc=0; wait "$rpid" || rc=$?
  exec 4>&-
  assert_eq "SIGTERM after a result line still writes interrupted" "interrupted" "$(marker_state "$(last_body)")"
  assert_eq "...and exits 143" "143" "$rc"
  assert_has "...and the hand-over is printed" "jikkyo: state interrupted" "$(cat "$TMP/out-late")"
  rm -f "$fifo"
}

echo "launch.sh"
{
  repo="$TMP/repo"
  git init -q "$repo"
  git -C "$repo" remote add origin https://github.com/o/r.git
  export CLAUDE_ARGS="$TMP/claude-args" CLAUDE_STREAM="$TMP/launch-stream.jsonl"
  { create t1 1; update u1 1 completed; result_ok; } > "$CLAUDE_STREAM"

  for bad_url in "" "https://github.com/o/r/pull/12" "http://github.com/o/r/issues/12" \
      "https://github.com/o/r/issues/12#issuecomment-1" "https://github.com/o/r/issues/12/" \
      "o/r#12" "12" "https://github.com/o/r/issues/12; rm -rf ~" \
      "https://github.com/o/r/issues/12'\"\$(id)" "https://gitlab.com/o/r/issues/12" \
      "https://github.com/o/r/issues/0"; do
    rm -f "$CLAUDE_ARGS"; new_log
    rc=0; (cd "$repo" && bash "$LAUNCH" "$bad_url") >/dev/null 2>&1 || rc=$?
    if [ "$rc" = 2 ] && [ ! -e "$CLAUDE_ARGS" ] && [ "$(calls)" = 0 ]; then
      ok "rejects [$bad_url] without starting the child"
    else bad "rejects [$bad_url] without starting the child (rc=$rc)"; fi
  done

  rm -f "$CLAUDE_ARGS"
  rc=0; (cd "$repo" && bash "$LAUNCH" "https://github.com/someone/else/issues/12") >/dev/null 2>&1 || rc=$?
  if [ "$rc" = 2 ] && [ ! -e "$CLAUDE_ARGS" ]; then ok "rejects an issue whose repository is not a remote here"
  else bad "rejects an issue whose repository is not a remote here (rc=$rc)"; fi

  rm -f "$CLAUDE_ARGS"
  rc=0; (cd "$TMP" && bash "$LAUNCH" "$URL") >/dev/null 2>&1 || rc=$?
  if [ "$rc" = 2 ] && [ ! -e "$CLAUDE_ARGS" ]; then ok "rejects a run outside a git repository"
  else bad "rejects a run outside a git repository (rc=$rc)"; fi

  new_log
  out="$(cd "$repo/" && echo "caller's stdin" | bash "$LAUNCH" "$URL" 2>&1)"
  args="$(cat "$CLAUDE_ARGS" 2>/dev/null)"
  assert_eq "the child's stdin is /dev/null, not the caller's" "" "$(cat "$CLAUDE_ARGS.stdin" 2>/dev/null)"
  assert_eq "the child gets CLAUDE_CODE_ENABLE_TODO_TOOLS=1" "1" "$(cat "$CLAUDE_ARGS.env" 2>/dev/null)"
  assert_eq "-p comes first" "-p" "$(printf '%s\n' "$args" | sed -n '1p')"
  prompt="$(printf '%s\n' "$args" | sed -n '2p')"
  assert_eq "the prompt starts with '/goal <URL> '" "/goal $URL " "${prompt:0:$(( ${#URL} + 7 ))}"
  assert_eq "the todo instruction comes right after the URL" "/goal $URL Todos: " "${prompt:0:$(( ${#URL} + 14 ))}"
  assert_has "the prompt asks for todos up front with TaskCreate" "before starting the work, break it into small steps with TaskCreate, one todo per step of a few minutes each" "$prompt"
  assert_has "...completed with TaskUpdate as each step is done" "mark each todo completed with TaskUpdate as soon as that step is done" "$prompt"
  assert_has "...new todos as new steps come up" "add todos with TaskCreate when new steps come up" "$prompt"
  assert_has "...one todo per task-list item when the issue has one" 'If the body of this issue has a task list (for example under "Acceptance criteria"), make one todo per task-list item' "$prompt"
  assert_has "...and ticks its box right after completing that todo" "tick the box of that item right after you mark its todo completed" "$prompt"
  assert_has "...and says why: progress and remaining time come from them" "Progress and the remaining time shown on the issue are computed from these todos." "$prompt"
  todo_at="${prompt%%Todos: *}"; tick_at="${prompt%%Task-list boxes: *}"
  if [ "${#todo_at}" -lt "${#tick_at}" ]; then ok "the todo instruction comes before the tick instruction"
  else bad "the todo instruction comes before the tick instruction"; fi
  assert_has "the prompt asks the child to tick verified boxes" "tick that box on the issue" "$prompt"
  assert_has "...as soon as each item is verified" "as soon as a task-list item in the body of this issue" "$prompt"
  assert_has "...before moving on, not saved for the end" "before you move on to the next item; do not save the ticks for one edit at the end" "$prompt"
  assert_has "...only verified ones, never untick or reword" "Tick only items you have verified, and never untick or reword anything." "$prompt"
  assert_has "...changing only - [ ] to - [x]" 'Change nothing in the body but "- [ ]" to "- [x]" on those lines' "$prompt"
  assert_has "...fetching the body right before each edit" "fetch the current body right before each edit" "$prompt"
  assert_has "...and the goal includes the ticks" "every box you could verify is ticked" "$prompt"
  assert_eq "the prompt is one argument on one line (--worktree follows it)" "--worktree" "$(printf '%s\n' "$args" | sed -n '3p')"
  name="$(printf '%s\n' "$args" | awk 'prev == "--worktree" { print; exit } { prev = $0 }')"
  if [[ "$name" =~ ^jikkyo-12-[0-9]{8}-[0-9]{6}$ ]]; then ok "--worktree jikkyo-<N>-<timestamp> ($name)"
  else bad "--worktree jikkyo-<N>-<timestamp> (got [$name])"; fi
  assert_has "--output-format stream-json" "$(printf -- '--output-format\nstream-json')" "$args"
  assert_has "--verbose" "--verbose" "$args"
  assert_has "--permission-mode auto" "$(printf -- '--permission-mode\nauto')" "$args"
  deny="$(printf '%s\n' "$args" | sed -n '/^--disallowedTools$/,$p' | sed '1d')"
  for rule in \
    'Bash(git push*--force*)' 'Bash(git push -f*)' 'Bash(git push * -f*)' 'Bash(git push * +*)' \
    'Bash(git push*--delete*)' 'Bash(git push -d*)' 'Bash(git push * -d*)' 'Bash(git push * :*)' \
    'Bash(git push*--mirror*)' 'Bash(git push*--prune*)' \
    'Bash(gh issue comment*--edit-last*)' 'Bash(gh issue comment*--delete-last*)' \
    'Bash(gh api*issues/comments/*)' 'Bash(gh api graphql*updateIssueComment*)' 'Bash(gh api*DELETE*)' \
    'Bash(gh issue close*)' 'Bash(gh issue delete*)' 'Bash(gh api*state=closed*)' \
    'Bash(gh api graphql*closeIssue*)' 'Bash(gh api graphql*deleteIssue*)'; do
    if printf '%s\n' "$deny" | grep -qxF -- "$rule"; then ok "deny list has $rule"; else bad "deny list has $rule"; fi
  done
  assert_eq "the deny list is exactly these 20 rules, last on the line" "20" "$(printf '%s\n' "$deny" | grep -c .)"
  assert_lacks "plain git push stays allowed" "Bash(git push)" "$deny"
  assert_lacks "plain git push stays allowed (no catch-all)" "Bash(git push*)" "$deny"

  root="$(cd "$repo" && pwd -P)"
  first3="$(printf '%s\n' "$out" | sed -n '1,3p')"
  assert_eq "prints the worktree name, path, and branch first" \
    "$(printf 'jikkyo: worktree name %s\njikkyo: worktree path %s/.claude/worktrees/%s\njikkyo: worktree branch worktree-%s' "$name" "$root" "$name" "$name")" \
    "$first3"
  # report.sh and the child start side by side, so only "after line 3" is fixed.
  assert_eq "...before the child starts" "4" \
    "$(( $(printf '%s\n' "$out" | grep -n '^child-started$' | cut -d: -f1) >= 4 ? 4 : 0 ))"
  assert_has "the child's stream is reported on the issue" "state=finished" "$(last_body)"
  assert_eq "launch.sh passes the worktree branch to report.sh, into the marker" \
    "<!-- jikkyo:status v=1 state=finished branch=worktree-$name -->" "$(last_body | head -n 1)"
  assert_has "...and into the Branch row" "| Branch | \`worktree-$name\` |" "$(last_body)"
  assert_has "the final message reaches the output" "All done. Opened PR #99." "$out"

  # From a subdirectory the worktree path is still under the repository root.
  mkdir -p "$repo/sub/dir"
  out="$(cd "$repo/sub/dir" && bash "$LAUNCH" "$URL" 2>&1 < /dev/null)"
  assert_has "from a subdirectory the path is under the repository root" "jikkyo: worktree path $root/.claude/worktrees/jikkyo-12-" "$out"

  # A host that merely ends in github.com does not count.
  git -C "$repo" remote set-url origin https://notgithub.com/o/r.git
  rm -f "$CLAUDE_ARGS"; rc=0; (cd "$repo" && bash "$LAUNCH" "$URL") >/dev/null 2>&1 < /dev/null || rc=$?
  if [ "$rc" = 2 ] && [ ! -e "$CLAUDE_ARGS" ]; then ok "a remote on notgithub.com does not match"
  else bad "a remote on notgithub.com does not match (rc=$rc)"; fi

  # An SSH remote counts too.
  git -C "$repo" remote set-url origin git@github.com:O/R.git
  rm -f "$CLAUDE_ARGS"; out="$(cd "$repo" && bash "$LAUNCH" "$URL" 2>&1 < /dev/null)"
  if [ -e "$CLAUDE_ARGS" ]; then ok "an SSH remote (any case) matches the issue's repository"
  else bad "an SSH remote (any case) matches the issue's repository ($out)"; fi
}

# ===========================================================================
echo "precheck.sh"
{
  NOW=1763000000   # an epoch; comments are dated relative to it
  iso() { date -u -d "@$1" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date -u -r "$1" '+%Y-%m-%dT%H:%M:%SZ'; }
  comment() {  # <id> <login> <state or "none"> <age seconds>
    local b
    if [ "$3" = none ]; then b="just a comment mentioning jikkyo:status state=running"
    else b="$(printf '<!-- jikkyo:status v=1 state=%s -->\n### jikkyo · %s · 50%%\n\n| Field | Value |\n| --- | --- |\n| State | %s |' "$3" "$3" "$3")"; fi
    jq -cn --argjson id "$1" --arg login "$2" --arg b "$b" --arg at "$(iso $((NOW - $4)))" \
      '{id: $id, html_url: ("https://github.com/o/r/issues/12#issuecomment-" + ($id | tostring)),
        user: {login: $login}, body: $b, created_at: $at, updated_at: $at}'
  }
  decide() { jq -s '.' | bash "$PRECHECK" --author me --now "$NOW" "$@"; }

  assert_eq "no comments: start" "start" "$(echo '[]' | bash "$PRECHECK" --author me --now "$NOW")"
  assert_eq "a live running comment: refuse with its URL" \
    "refuse https://github.com/o/r/issues/12#issuecomment-1" "$(comment 1 me running 60 | decide)"
  assert_eq "running, updated 14 m 59 s ago: still live" \
    "refuse https://github.com/o/r/issues/12#issuecomment-1" "$(comment 1 me running 899 | decide)"
  assert_eq "running, not updated for 15 minutes: rewrite, then start" "rewrite 1" "$(comment 1 me running 900 | decide)"
  assert_eq "--force skips the check and rewrites a live one" "rewrite 1" "$(comment 1 me running 60 | decide --force)"
  assert_eq "--force with nothing running: start" "start" "$(comment 1 me finished 60 | decide --force)"
  for st in finished failed interrupted; do
    assert_eq "a $st comment never blocks" "start" "$(comment 1 me "$st" 1 | decide)"
  done
  assert_eq "another author's marker does not count" "start" "$(comment 1 someone running 60 | decide)"
  assert_eq "a comment without the marker does not count" "start" "$(comment 1 me none 60 | decide)"
  assert_eq "a live run blocks even next to a stale one" \
    "refuse https://github.com/o/r/issues/12#issuecomment-2" "$( { comment 1 me running 5000; comment 2 me running 10; } | decide)"
  assert_eq "every stale running comment is rewritten" "rewrite 1 3" \
    "$( { comment 1 me running 5000; comment 2 me finished 10; comment 3 me running 901; } | decide)"
  # gh api --paginate prints one array per page.
  pages="$(printf '%s\n%s\n' "$(comment 1 me finished 1 | jq -s .)" "$(comment 2 me running 60 | jq -s .)")"
  assert_eq "several pages are read as one list" \
    "refuse https://github.com/o/r/issues/12#issuecomment-2" "$(printf '%s\n' "$pages" | bash "$PRECHECK" --author me --now "$NOW")"
  # GitHub sometimes returns fractional seconds.
  frac="$(comment 1 me running 60 | jq -c '.updated_at |= sub("Z$"; ".123Z")')"
  assert_eq "fractional-second timestamps are read" \
    "refuse https://github.com/o/r/issues/12#issuecomment-1" "$(printf '[%s]' "$frac" | bash "$PRECHECK" --author me --now "$NOW")"

  rc=0; echo '[]' | bash "$PRECHECK" >/dev/null 2>&1 || rc=$?
  assert_eq "--author is required" "2" "$rc"
  rc=0; echo 'nope' | bash "$PRECHECK" --author me >/dev/null 2>&1 || rc=$?
  assert_eq "input that is not JSON is an error" "2" "$rc"
  rc=0; out="$(printf '' | bash "$PRECHECK" --author me 2>/dev/null)" || rc=$?
  assert_eq "empty input (a failed listing) is an error, not start" "2:" "$rc:$out"
  rc=0; out="$(echo '{"message":"Bad credentials"}' | bash "$PRECHECK" --author me 2>/dev/null)" || rc=$?
  assert_eq "an API error object is an error, not start" "2:" "$rc:$out"

  p="$(comment 1 me running 5000 | bash "$PRECHECK" --payload | jq -r .body)"
  assert_eq "--payload rewrites the marker to interrupted" "<!-- jikkyo:status v=1 state=interrupted -->" "$(printf '%s\n' "$p" | head -n 1)"
  assert_has "--payload rewrites the heading" "### jikkyo · interrupted · 50%" "$p"
  assert_has "--payload rewrites the State row" "| State | interrupted |" "$p"
  eta_body="$(printf '%s\n' '<!-- jikkyo:status v=1 state=running -->' '### jikkyo · running · 37% · ~12m 30s left' '' \
    '| Field | Value |' '| --- | --- |' '| State | running |' '| Elapsed | 7m 30s |' \
    '| Remaining | ~12m 30s (estimate) |')"
  p="$(jq -cn --arg b "$eta_body" '{id: 1, body: $b}' | bash "$PRECHECK" --payload | jq -r .body)"
  assert_eq "--payload drops the estimate from the heading" "### jikkyo · interrupted · 37%" "$(heading "$p")"
  assert_eq "--payload empties the Remaining row" "| Remaining |  |" "$(printf '%s\n' "$p" | grep '^| Remaining')"
  assert_has "--payload keeps the Elapsed row" "| Elapsed | 7m 30s |" "$p"
  # A comment posted before the row was renamed carries the old fraction and
  # the old `Remaining (est.)` label; it is emptied the same way.
  old_body="$(printf '%s\n' '<!-- jikkyo:status v=1 state=running -->' '### jikkyo · running · 3/8 (37%) · ~12m 30s left' '' \
    '| Field | Value |' '| --- | --- |' '| State | running |' '| Elapsed | 7m 30s |' \
    '| Remaining (est.) | ~12m 30s (estimate, from 3/8 todos) |')"
  p="$(jq -cn --arg b "$old_body" '{id: 1, body: $b}' | bash "$PRECHECK" --payload | jq -r .body)"
  assert_eq "--payload, old format: drops the estimate from the heading" "### jikkyo · interrupted · 3/8 (37%)" "$(heading "$p")"
  assert_eq "--payload, old format: empties the Remaining (est.) row" "| Remaining (est.) |  |" "$(printf '%s\n' "$p" | grep '^| Remaining')"
  assert_has "--payload, old format: keeps the Elapsed row" "| Elapsed | 7m 30s |" "$p"
  rc=0; comment 1 me finished 10 | bash "$PRECHECK" --payload >/dev/null 2>&1 || rc=$?
  assert_eq "--payload refuses a comment that is not running" "1" "$rc"

  # Markers with the run's branch after the state (report.sh writes them since
  # #28) are read like the ones without it.
  BR="worktree-jikkyo-12-20261114-132452"
  br_comment() {  # <id> <login> <state> <age seconds>
    comment "$1" "$2" "$3" "$4" | jq -c --arg br "$BR" '.body |= sub(" -->"; " branch=\($br) -->")'
  }
  assert_has "br_comment builds a marker with branch=" "state=running branch=$BR -->" "$(br_comment 1 me running 60 | jq -r .body)"
  assert_eq "branch=: a live running comment: refuse" \
    "refuse https://github.com/o/r/issues/12#issuecomment-1" "$(br_comment 1 me running 60 | decide)"
  assert_eq "branch=: a stale running comment: rewrite" "rewrite 1" "$(br_comment 1 me running 900 | decide)"
  for st in finished failed interrupted; do
    assert_eq "branch=: a $st comment never blocks" "start" "$(br_comment 1 me "$st" 1 | decide)"
  done
  assert_eq "stale comments with and without branch= are both rewritten" "rewrite 1 2" \
    "$( { comment 1 me running 5000; br_comment 2 me running 5000; } | decide)"
  assert_eq "a marker with a malformed branch= does not count" "start" \
    "$(comment 1 me running 60 | jq -c '.body |= sub(" -->"; " branch=main -->")' | decide)"
  p="$(br_comment 1 me running 5000 | bash "$PRECHECK" --payload | jq -r .body)"
  assert_eq "--payload with branch=: interrupted, and the branch is kept" \
    "<!-- jikkyo:status v=1 state=interrupted branch=$BR -->" "$(printf '%s\n' "$p" | head -n 1)"
  assert_has "--payload with branch=: the heading" "### jikkyo · interrupted · 50%" "$p"
  assert_has "--payload with branch=: the State row" "| State | interrupted |" "$p"
  rc=0; br_comment 1 me finished 10 | bash "$PRECHECK" --payload >/dev/null 2>&1 || rc=$?
  assert_eq "--payload with branch=: refuses a comment that is not running" "1" "$rc"
  # Comments report.sh itself wrote with a branch, end to end, in both languages.
  p="$(jq -cn --arg b "$BR_RUNNING_BODY" '{id: 1, body: $b}' | bash "$PRECHECK" --payload | jq -r .body)"
  assert_eq "--payload on report.sh's own branch= comment: the marker" \
    "<!-- jikkyo:status v=1 state=interrupted branch=$BR -->" "$(printf '%s\n' "$p" | head -n 1)"
  assert_eq "...the heading" "### jikkyo · interrupted · 0 turns" "$(heading "$p")"
  assert_has "...and the Branch row is kept" "| Branch | \`$BR\` |" "$p"
  p="$(jq -cn --arg b "$BR_RUNNING_BODY_JA" '{id: 1, body: $b}' | bash "$PRECHECK" --payload | jq -r .body)"
  assert_eq "--payload on report.sh's own Japanese branch= comment: the marker" \
    "<!-- jikkyo:status v=1 state=interrupted branch=$BR -->" "$(printf '%s\n' "$p" | head -n 1)"
  assert_eq "...the heading" "### jikkyo · 中断 · 0 ターン" "$(heading "$p")"
  assert_has "...and the ブランチ row is kept" "| ブランチ | \`$BR\` |" "$p"

  # Japanese status comments: the marker is the same, so the decisions are too.
  ja_comment() {  # <id> <login> <state> <age seconds>
    local w b
    case "$3" in running) w="実行中" ;; finished) w="完了" ;; failed) w="失敗" ;; interrupted) w="中断" ;; esac
    b="$(printf '<!-- jikkyo:status v=1 state=%s -->\n### jikkyo · %s · 50%%\n\n| 項目 | 値 |\n| --- | --- |\n| 状態 | %s |' "$3" "$w" "$w")"
    jq -cn --argjson id "$1" --arg login "$2" --arg b "$b" --arg at "$(iso $((NOW - $4)))" \
      '{id: $id, html_url: ("https://github.com/o/r/issues/12#issuecomment-" + ($id | tostring)),
        user: {login: $login}, body: $b, created_at: $at, updated_at: $at}'
  }
  assert_eq "Japanese: a live running comment: refuse" \
    "refuse https://github.com/o/r/issues/12#issuecomment-1" "$(ja_comment 1 me running 60 | decide)"
  assert_eq "Japanese: a stale running comment: rewrite" "rewrite 1" "$(ja_comment 1 me running 900 | decide)"
  for st in finished failed interrupted; do
    assert_eq "Japanese: a $st comment never blocks" "start" "$(ja_comment 1 me "$st" 1 | decide)"
  done
  assert_eq "a stale English and a stale Japanese comment are both rewritten" "rewrite 1 2" \
    "$( { comment 1 me running 5000; ja_comment 2 me running 5000; } | decide)"

  p="$(ja_comment 1 me running 5000 | bash "$PRECHECK" --payload | jq -r .body)"
  assert_eq "Japanese --payload: the marker becomes interrupted" "<!-- jikkyo:status v=1 state=interrupted -->" "$(printf '%s\n' "$p" | head -n 1)"
  assert_eq "Japanese --payload: the heading" "### jikkyo · 中断 · 50%" "$(heading "$p")"
  assert_has "Japanese --payload: the State row" "| 状態 | 中断 |" "$p"
  assert_lacks "Japanese --payload: no running word left" "実行中" "$p"
  # The comment report.sh itself wrote above, with an estimate in it.
  p="$(jq -cn --arg b "$JA_ETA_BODY" '{id: 1, body: $b}' | bash "$PRECHECK" --payload | jq -r .body)"
  assert_eq "Japanese --payload: drops the estimate from the heading" "### jikkyo · 中断 · 25%" "$(heading "$p")"
  assert_eq "Japanese --payload: empties the Remaining row" "| 残り |  |" "$(printf '%s\n' "$p" | grep '^| 残り')"
  assert_has "Japanese --payload: keeps the Elapsed row" "| 経過 | 2m 30s |" "$p"
  assert_has "Japanese --payload: keeps the Progress row" "| 進捗 | 25% |" "$p"
  # An English comment from report.sh, likewise, end to end.
  p="$(comment 1 me running 5000 | bash "$PRECHECK" --payload | jq -r .body)"
  assert_lacks "English --payload: no Japanese appears" "中断" "$p"
}

# ===========================================================================
echo "cleanup.sh"
{
  base="$TMP/cleanup"
  git init -q --bare "$base/remote.git"
  git clone -q "$base/remote.git" "$base/main" 2>/dev/null
  g() { git -C "$@"; }
  g "$base/main" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
  g "$base/main" push -q origin HEAD:main 2>/dev/null
  g "$base/main" fetch -q origin
  wt() {  # <name>: a fresh worktree on a new branch from origin/main
    g "$base/main" worktree add -q -b "worktree-$1" "$base/main/.claude/worktrees/$1" origin/main 2>/dev/null
    echo "$base/main/.claude/worktrees/$1"
  }
  first() { bash "$CLEANUP" "$1" | head -n 1; }

  w="$(wt clean)"
  assert_eq "clean, no new commits: remove" "remove" "$(first "$w")"

  w="$(wt untracked)"; echo x > "$w/new.txt"
  assert_eq "an untracked file: keep" "keep" "$(first "$w")"

  w="$(wt modified)"; echo x > "$w/f.txt"; g "$w" add f.txt; g "$w" -c user.name=t -c user.email=t@t commit -q -m f
  echo y > "$w/f.txt"
  assert_eq "a modified tracked file: keep" "keep" "$(first "$w")"

  w="$(wt staged)"; echo x > "$w/s.txt"; g "$w" add s.txt
  assert_eq "a staged change: keep" "keep" "$(first "$w")"

  w="$(wt unpushed)"; echo x > "$w/u.txt"; g "$w" add u.txt; g "$w" -c user.name=t -c user.email=t@t commit -q -m u
  assert_eq "a commit that is not pushed: keep" "keep" "$(first "$w")"
  assert_has "keep says why" "not pushed" "$(bash "$CLEANUP" "$w")"

  w="$(wt pushed)"; echo x > "$w/p.txt"; g "$w" add p.txt; g "$w" -c user.name=t -c user.email=t@t commit -q -m p
  g "$w" push -q -u origin worktree-pushed 2>/dev/null
  assert_eq "commits pushed, nothing uncommitted: remove" "remove" "$(first "$w")"

  echo z > "$w/after.txt"
  assert_eq "pushed but then dirty: keep" "keep" "$(first "$w")"
  g "$w" add after.txt; g "$w" -c user.name=t -c user.email=t@t commit -q -m after
  assert_eq "pushed, then a new commit that is not pushed: keep" "keep" "$(first "$w")"

  assert_eq "a missing worktree: keep" "keep" "$(first "$base/nope")"
  mkdir -p "$base/plain"
  assert_eq "a directory that is not a worktree: keep" "keep" "$(first "$base/plain")"
  mkdir -p "$base/main/.claude/worktrees/clean/sub"
  assert_eq "a path inside a worktree, not its top: keep" "keep" "$(first "$base/main/.claude/worktrees/clean/sub")"

  rc=0; bash "$CLEANUP" >/dev/null 2>&1 || rc=$?
  assert_eq "no argument is a usage error" "2" "$rc"
}

# ===========================================================================
echo "SKILL.md"
{
  # SKILL.md runs each script by its path, not through `bash`, and the
  # allowed-tools rules match that form, so every script must be executable.
  for s in launch report precheck cleanup; do
    if [ -x "$SCRIPTS/$s.sh" ]; then ok "$s.sh is executable"; else bad "$s.sh is executable"; fi
  done
  fm="$(awk 'NR == 1 && /^---$/ { on = 1; next } on && /^---$/ { exit } on' "$SKILL_MD")"
  assert_has "name is jikkyo" "name: jikkyo" "$fm"
  allowed="$(printf '%s\n' "$fm" | sed -n 's/^allowed-tools: //p')"
  for s in launch precheck cleanup; do
    assert_has "allowed-tools pins $s.sh with \${CLAUDE_SKILL_DIR}" "Bash(\${CLAUDE_SKILL_DIR}/scripts/$s.sh *)" "$allowed"
  done
  assert_lacks "allowed-tools does not pre-approve claude -p" "claude" "$allowed"
  assert_lacks "allowed-tools does not pre-approve gh" "gh " "$allowed"
  assert_lacks "allowed-tools does not pre-approve git" "git " "$allowed"
  skill="$(cat "$SKILL_MD")"
  assert_has "SKILL.md: the summary is in the status comment's language" "Write it in the same language as the status comment" "$skill"
  assert_has "SKILL.md: the parent reads the language line" "jikkyo: language ja|en" "$skill"
  assert_eq "allowed-tools has exactly three rules" "3" "$(printf '%s\n' "$allowed" | grep -o 'Bash(' | wc -l | tr -d ' ')"
  # shellcheck disable=SC2016  # a literal backtick pattern
  if grep -n '^ *!`\|^```!' "$SKILL_MD" | grep -q .; then bad "SKILL.md has no injected commands"
  else ok "SKILL.md has no injected commands"; fi
}

echo
echo "total: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
