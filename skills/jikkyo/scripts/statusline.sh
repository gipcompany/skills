#!/usr/bin/env bash
#
# statusline.sh — show this session's jikkyo runs in the Claude Code status
# line.
#
#   {"statusLine": {"type": "command", "command": "<skill dir>/scripts/statusline.sh", "refreshInterval": 10}}
#
# It reads the status line's JSON on stdin (session_id, and for the directory
# the first of workspace.project_dir, workspace.current_dir, and cwd that is
# inside a git checkout), finds the state files report.sh writes in that
# checkout's git common dir
# (<git common dir>/jikkyo/<N>.json), and prints one line with a segment for
# each run whose `session` is this session_id, ordered by issue number and
# joined with ` | `:
#
#   jikkyo #27 · 60% · ~12m left | jikkyo #31 · finished
#
#   - running: `jikkyo #<N> · <pct>% · ~<eta> left` (no ` · ~<eta> left`
#     before the first completed todo), or `jikkyo #<N> · <turns> turns`
#     when the run has no todos. <eta> is the estimate as of the last write,
#     the same figure as the status comment's `Remaining` row; it does not
#     count down between writes (at most 5 minutes apart, the heartbeat);
#   - finished, incomplete, failed, interrupted: `jikkyo #<N> · <state>` for 5 minutes
#     after the file's `updated`, then nothing;
#   - stale: `jikkyo #<N> · stale` for a `running` file whose `updated` is 15
#     minutes old or more, for as long as the file stays (until the next run
#     of the issue overwrites it). report.sh writes `interrupted` on TERM,
#     HUP, and INT, so a file is left at `running` only after a SIGKILL or a
#     crash, and the status line may be the only sign left. A live run shown
#     as stale (after sleep, say) clears on its next heartbeat.
#
# Each segment is in its run's status-comment language (`lang` in the state
# file), using the comment's own Japanese words for `ja`:
#
#   jikkyo #27 · 60% · 残り ~12m | jikkyo #28 · 12 ターン | jikkyo #31 · 完了
#
# (未完了 incomplete, 失敗 failed, 中断 interrupted, 応答なし stale).
#
# Only the session that launched (or resumed) a run shows it: launch.sh gets
# that session's ${CLAUDE_SESSION_ID} and report.sh records it as `session`.
# With no matching run it prints nothing. What it shows is a convenience, not
# a record: anything that can write to the git common dir can write a state
# file, so the status comment on the issue is where a run's state is settled.
#
# It is local and quiet: no network and no `gh`, only local tools (`git
# rev-parse`, `find`, `awk`, `head`, `date`, `jq`, and `cat` for the test
# clock) on local files. It prints nothing but numbers it has checked and the
# fixed words above, so no text from an issue or a terminal escape sequence
# can reach the terminal. A state file that is malformed, too large, not a
# regular file, unreadable, not of this session, or written more than a
# minute in the future is skipped; anything else that goes wrong (no jq, bad
# stdin, not a git checkout) prints nothing. It always exits 0 and writes
# nothing to stderr, so it never breaks the status line it is part of. These
# checks are made when the files are listed: a file swapped afterwards for a
# bigger one is read whole, and one swapped for a FIFO can hold the line up
# until Claude Code gives up on the command.
#
# For tests: JIKKYO_CLOCK_FILE (read "now" in epoch seconds from this file).
#
set -uo pipefail

ENDED_SHOWN=300   # seconds an ended run stays on the line
# A `running` file not rewritten for this long belongs to a run that is gone:
# the heartbeat rewrites it every 5 minutes. The same threshold as precheck.sh.
STALE_AFTER=900

now() {
  if [ -n "${JIKKYO_CLOCK_FILE:-}" ]; then cat "$JIKKYO_CLOCK_FILE"; else date '+%s'; fi
}

# fmt_eta <seconds>: 45s, 12m, 1h 05m.
fmt_eta() {
  local s="$1"
  if [ "$s" -lt 60 ]; then printf '%ds' "$s"
  elif [ "$s" -lt 3600 ]; then printf '%dm' $((s / 60))
  else printf '%dh %02dm' $((s / 3600)) $((s % 3600 / 60)); fi
}

# segment <number> <kind> <pct> <eta> <turns> <lang>: one run's segment, in
# the status comment's language. The Japanese words are the status comment's
# own labels (report.sh's set_labels and state_word), so the two agree;
# `stale` has no label there and is 応答なし ("no response").
segment() {
  local n="$1" kind="$2" pct="$3" eta="$4" turns="$5" lang="$6" seg="jikkyo #$1"
  case "$kind" in
    running)
      if [ "$pct" -ge 0 ]; then
        seg="${seg} · ${pct}%"
        if [ "$eta" -ge 0 ]; then
          if [ "$lang" = ja ]; then seg="${seg} · 残り ~$(fmt_eta "$eta")"
          else seg="${seg} · ~$(fmt_eta "$eta") left"; fi
        fi
      elif [ "$lang" = ja ]; then seg="${seg} · ${turns} ターン"
      elif [ "$turns" = 1 ]; then seg="${seg} · 1 turn"
      else seg="${seg} · ${turns} turns"; fi ;;
    finished | incomplete | failed | interrupted | stale)
      if [ "$lang" = ja ]; then
        case "$kind" in
          finished) seg="${seg} · 完了" ;; incomplete) seg="${seg} · 未完了" ;;
          failed) seg="${seg} · 失敗" ;; interrupted) seg="${seg} · 中断" ;;
          stale) seg="${seg} · 応答なし" ;;
        esac
      else seg="${seg} · ${kind}"; fi ;;
    *) return 1 ;;
  esac
  printf '%s' "$seg"
}

# One line per run to show, tab-separated: number, kind (running, stale, or
# the ended state), percentage (-1 with no todos), eta seconds (-1 for none),
# turns, and language. The input is every line of the state files as
# `<path>\t<line>` (one awk for all of them, which ends each file's last line
# even without a newline), so a malformed one is skipped without taking the
# others down. A state file is one line of JSON (report.sh writes it with
# jq -c); a pretty-printed one is skipped, and should a file hold several
# lines, the last of those still on show is used.
# A file whose `updated` is more than a minute in the future (the clock was
# set back since it was written) is skipped, or an ended run would stay on
# the line until the clock caught up.
# shellcheck disable=SC2016  # jq program
SELECT='
def nat: type == "number" and . >= 0 and . == floor;
[ inputs
  | index("\t") as $tab
  | select($tab != null)
  | (.[:$tab] | sub("^.*/"; "")) as $file
  | (.[$tab + 1:] | try fromjson catch null) as $j
  | select($j | type == "object")
  | $j
  | select(.v == 1 and (.number | nat) and .number > 0 and ($file == "\(.number).json"))
  | select(.session == $sid)
  | select(.state | IN("running", "finished", "incomplete", "failed", "interrupted"))
  | select((.done | nat) and (.total | nat) and (.turns | nat) and .done <= .total and (.updated | nat))
  | select(.eta_secs == null or (.eta_secs | nat))
  | select(.lang | IN("en", "ja"))
  | ($now - .updated) as $age
  | select($age >= -60)
  | if .state == "running" and $age >= $stale_after then .kind = "stale"
    elif .state == "running" then .kind = "running"
    elif $age < $ended_shown then .kind = .state
    else empty end
  | {n: .number, kind,
     pct: (if .total > 0 then (.done * 100 / .total | floor) else -1 end),
     eta: (.eta_secs // -1), turns, lang}
]
| group_by(.n) | map(last) | sort_by(.n) | .[]
| [.n, .kind, .pct, .eta, .turns, .lang] | @tsv
'

main() {
  local input sid="" d common="" t f n kind pct eta turns seg line=""
  local -a dirs=() files=()
  command -v jq >/dev/null 2>&1 || return 0
  input="$(head -c 1048576)" || return 0
  # The session id, then the candidate directories, NUL-separated: where
  # Claude Code was started, the current directory, and cwd, in that order.
  {
    IFS= read -r -d '' sid || return 0
    while IFS= read -r -d '' d; do dirs+=("$d"); done
  } < <(jq -j '((.session_id | strings) // "") + "\u0000",
               ((.workspace.project_dir, .workspace.current_dir, .cwd) | strings | . + "\u0000")' <<<"$input")
  [[ "$sid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || return 0
  # The first of them inside a git checkout: Claude Code may have been
  # started outside the repository and moved into it.
  for d in ${dirs[@]+"${dirs[@]}"}; do
    case "$d" in /*) ;; *) continue ;; esac
    [ -d "$d" ] || continue
    common="$(git -C "$d" rev-parse --path-format=absolute --git-common-dir)" && [ -n "$common" ] && break
    common=""
  done
  [ -n "$common" ] && [ -d "$common/jikkyo" ] || return 0
  # One find for all the state files: regular files only (a FIFO would
  # block), at most 4 KiB each.
  # Readable ones only: mawk and BSD awk stop at the first file they cannot
  # open, which would take the others down with it. The 4 KiB cap and the
  # regular-file check hold at find time only (see the top of this file).
  while IFS= read -r -d '' f; do [ -r "$f" ] && files+=("$f"); done \
    < <(find "$common/jikkyo" -maxdepth 1 -type f -name '[1-9]*.json' -size -4097c -print0)
  [ "${#files[@]}" -gt 0 ] || return 0
  t="$(now)"
  [[ "$t" =~ ^[0-9]+$ ]] || return 0
  while IFS=$'\t' read -r n kind pct eta turns lang; do
    # Only checked numbers and fixed words reach the terminal.
    [[ "$n" =~ ^[1-9][0-9]*$ && "$pct" =~ ^-?[0-9]+$ && "$eta" =~ ^-?[0-9]+$ && "$turns" =~ ^[0-9]+$ ]] || continue
    case "$lang" in en | ja) ;; *) continue ;; esac
    seg="$(segment "$n" "$kind" "$pct" "$eta" "$turns" "$lang")" || continue
    line="${line:+${line} | }${seg}"
  done < <(awk '{ print FILENAME "\t" $0 }' "${files[@]}" \
             | jq -n -R -r --arg sid "$sid" --argjson now "$t" --argjson ended_shown "$ENDED_SHOWN" \
                 --argjson stale_after "$STALE_AFTER" "$SELECT")
  [ -n "$line" ] && printf '%s\n' "$line"
  return 0
}

# Whatever goes wrong, print nothing rather than break the user's status line.
exec 2>/dev/null
main
exit 0
