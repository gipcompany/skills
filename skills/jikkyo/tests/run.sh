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
cat > "$STUBS/gh" <<'EOF'
#!/usr/bin/env bash
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
  assert_eq "completed / non-deleted tasks, with a deletion and a mid-run add" "### jikkyo · finished · 2/3 (66%)" "$(heading "$b")"
  assert_has "the table carries the progress row" "| Progress | 2/3 (66%) |" "$b"

  # The % can go down when the child adds tasks.
  f="$TMP/down.jsonl"
  { create a 1; create b 2; create c 3; create d 4
    update e 1 completed; update f 2 completed; update g 3 completed
    create h 5; create i 6; } > "$f"
  run_report "$f"
  assert_eq "progress drops when tasks are added (3/4 -> 3/6)" "### jikkyo · interrupted · 3/6 (50%)" "$(heading "$(last_body)")"

  # A TaskCreate whose result is an error creates nothing; neither does an
  # update to a task that was never created.
  f="$TMP/errors.jsonl"
  { create a 1
    assistant_tool b TaskCreate '{"subject":"x","description":"y"}'; tool_result b "boom" true
    update c 9 completed; update d 1 completed; result_ok; } > "$f"
  run_report "$f"
  assert_eq "failed creates and unknown task ids are ignored" "### jikkyo · finished · 1/1 (100%)" "$(heading "$(last_body)")"

  # The task id can also come from the structured tool_use_result.
  f="$TMP/structured.jsonl"
  { assistant_tool s1 TaskCreate '{"subject":"x","description":"y"}'
    jq -cn '{type: "user", tool_use_result: {task: {id: "5"}},
             message: {content: [{type: "tool_result", tool_use_id: "s1", content: [{type: "text", text: "ok"}]}]}}'
    update s2 5 completed; result_ok; } > "$f"
  run_report "$f"
  assert_eq "task id read from tool_use_result when the text has none" "### jikkyo · finished · 1/1 (100%)" "$(heading "$(last_body)")"

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
  assert_eq "unexpected event shapes are skipped and the run goes on" "### jikkyo · finished · 1/1 (100%)" "$(heading "$(last_body)")"
  assert_has "...and the final message still arrives" "All done. Opened PR #99." "$(cat "$TMP/out")"

  # Garbage lines do not end the run.
  f="$TMP/garbage.jsonl"
  { echo 'not json'; echo '[1,2]'; create a 1; update b 1 completed; result_ok; } > "$f"
  run_report "$f"
  assert_eq "lines that are not JSON objects are skipped" "### jikkyo · finished · 1/1 (100%)" "$(heading "$(last_body)")"
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
  assert_eq "the held write shows the change" "### jikkyo · running · 0/1 (0%)" "$(heading "$(last_body)")"

  at 1031; update u1 1 in_progress >&4; update u2 1 completed >&4; settle
  at 1059; settle
  assert_eq "back-to-back changes are coalesced and held" "2" "$(calls)"
  at 1060; settle
  assert_eq "they are written as one write" "3" "$(calls)"
  assert_eq "that write shows the latest state" "### jikkyo · running · 1/1 (100%) · ~0s left" "$(heading "$(last_body)")"

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
  assert_eq "the pending change is in the end write" "### jikkyo · interrupted · 1/2 (50%)" "$(heading "$(last_body)")"
  rm -f "$fifo"
}

# ===========================================================================
echo "report.sh: estimated time remaining"
{
  remaining() { printf '%s\n' "$1" | grep '^| Remaining (est.) |'; }
  new_log
  clock="$TMP/clock"; echo 1000 > "$clock"
  fifo="$TMP/fifo-eta"; rm -f "$fifo"; mkfifo "$fifo"
  JIKKYO_CLOCK_FILE="$clock" bash "$REPORT" "$URL" < "$fifo" > "$TMP/out" 2>&1 &
  rpid=$!
  exec 4> "$fifo"
  settle() { sleep 0.6; }

  settle
  b="$(last_body)"
  assert_eq "no todos: the Remaining row is empty" "| Remaining (est.) |  |" "$(remaining "$b")"
  assert_eq "no todos: no estimate in the heading" "### jikkyo · running · 0 turns" "$(heading "$b")"

  { create t1 1; create t2 2; create t3 3; create t4 4; } >&4
  echo 1060 > "$clock"; settle
  assert_eq "todos written" "2" "$(calls)"
  b="$(last_body)"
  assert_eq "none completed: the Remaining row is empty" "| Remaining (est.) |  |" "$(remaining "$b")"
  assert_eq "none completed: no estimate in the heading" "### jikkyo · running · 0/4 (0%)" "$(heading "$b")"

  # 150 s for 1 of 4 todos: 150 / 1 * 3 = 450 s left.
  update u1 1 completed >&4
  echo 1150 > "$clock"; settle
  assert_eq "progress written" "3" "$(calls)"
  b="$(last_body)"
  assert_eq "partial progress: the Remaining row has the estimate" \
    "| Remaining (est.) | ~7m 30s (estimate, from 1/4 todos) |" "$(remaining "$b")"
  assert_eq "partial progress: the heading carries the estimate" \
    "### jikkyo · running · 1/4 (25%) · ~7m 30s left" "$(heading "$b")"

  result_ok >&4
  exec 4>&-
  wait "$rpid"
  b="$(last_body)"
  assert_eq "finished: the Remaining row is empty" "| Remaining (est.) |  |" "$(remaining "$b")"
  assert_eq "finished: no estimate in the heading" "### jikkyo · finished · 1/4 (25%)" "$(heading "$b")"
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
  assert_has "the prompt asks the child to tick verified boxes" "tick that box on the issue" "$prompt"
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
    else b="$(printf '<!-- jikkyo:status v=1 state=%s -->\n### jikkyo · %s · 1/2 (50%%)\n\n| Field | Value |\n| --- | --- |\n| State | %s |' "$3" "$3" "$3")"; fi
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
  assert_has "--payload rewrites the heading" "### jikkyo · interrupted · 1/2 (50%)" "$p"
  assert_has "--payload rewrites the State row" "| State | interrupted |" "$p"
  eta_body="$(printf '%s\n' '<!-- jikkyo:status v=1 state=running -->' '### jikkyo · running · 3/8 (37%) · ~12m 30s left' '' \
    '| Field | Value |' '| --- | --- |' '| State | running |' '| Elapsed | 7m 30s |' \
    '| Remaining (est.) | ~12m 30s (estimate, from 3/8 todos) |')"
  p="$(jq -cn --arg b "$eta_body" '{id: 1, body: $b}' | bash "$PRECHECK" --payload | jq -r .body)"
  assert_eq "--payload drops the estimate from the heading" "### jikkyo · interrupted · 3/8 (37%)" "$(heading "$p")"
  assert_eq "--payload empties the Remaining row" "| Remaining (est.) |  |" "$(printf '%s\n' "$p" | grep '^| Remaining (est.) |')"
  assert_has "--payload keeps the Elapsed row" "| Elapsed | 7m 30s |" "$p"
  rc=0; comment 1 me finished 10 | bash "$PRECHECK" --payload >/dev/null 2>&1 || rc=$?
  assert_eq "--payload refuses a comment that is not running" "1" "$rc"
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
  assert_eq "allowed-tools has exactly three rules" "3" "$(printf '%s\n' "$allowed" | grep -o 'Bash(' | wc -l | tr -d ' ')"
  # shellcheck disable=SC2016  # a literal backtick pattern
  if grep -n '^ *!`\|^```!' "$SKILL_MD" | grep -q .; then bad "SKILL.md has no injected commands"
  else ok "SKILL.md has no injected commands"; fi
}

echo
echo "total: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
