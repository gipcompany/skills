#!/usr/bin/env bash
#
# statusline.sh — show this session's jikkyo runs in the Claude Code status
# line.
#
#   {"statusLine": {"type": "command", "command": "<skill dir>/scripts/statusline.sh", "refreshInterval": 10}}
#
# It reads the status line's JSON on stdin (session_id, and
# workspace.project_dir, workspace.current_dir, or cwd for the directory),
# finds the state files report.sh writes in that checkout's git common dir
# (<git common dir>/jikkyo/<N>.json), and prints one line with a segment for
# each run whose `session` is this session_id, ordered by issue number and
# joined with ` | `:
#
#   jikkyo #27 · 60% · ~12m left | jikkyo #31 · finished
#
#   - running: `jikkyo #<N> · <pct>% · ~<eta> left` (no ` · ~<eta> left`
#     before the first completed todo), or `jikkyo #<N> · <turns> turns`
#     when the run has no todos;
#   - finished, failed, interrupted: `jikkyo #<N> · <state>` for 5 minutes
#     after the file's `updated`, then nothing;
#   - stale: `jikkyo #<N> · stale` for a `running` file whose `updated` is 15
#     minutes old or more, for as long as the file stays (until the next run
#     of the issue overwrites it). report.sh writes `interrupted` on TERM,
#     HUP, and INT, so a file is left at `running` only after a SIGKILL or a
#     crash, and the status line may be the only sign left. A live run shown
#     as stale (after sleep, say) clears on its next heartbeat.
#
# Only the session that launched (or resumed) a run shows it: launch.sh gets
# that session's ${CLAUDE_SESSION_ID} and report.sh records it as `session`.
# With no matching run it prints nothing.
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

# One line per run to show, tab-separated: number, kind (running or the
# ended state), percentage (-1 with no todos), eta seconds (-1 for none), turns.
# shellcheck disable=SC2016  # jq program
SELECT='
def nat: type == "number" and . >= 0 and . == floor;
[ inputs
  | index("\t") as $tab
  | select($tab != null)
  | .[:$tab] as $file
  | (.[$tab + 1:] | try fromjson catch null) as $j
  | select($j | type == "object")
  | $j
  | select(.v == 1 and (.number | nat) and .number > 0 and ($file == "\(.number).json"))
  | select(.session == $sid)
  | select(.state | IN("running", "finished", "failed", "interrupted"))
  | select((.done | nat) and (.total | nat) and (.turns | nat) and .done <= .total and (.updated | nat))
  | select(.eta_secs == null or (.eta_secs | nat))
  | ($now - .updated) as $age
  | if .state == "running" and $age >= $stale_after then .kind = "stale"
    elif .state == "running" then .kind = "running"
    elif $age < $ended_shown then .kind = .state
    else empty end
  | {n: .number, kind,
     pct: (if .total > 0 then (.done * 100 / .total | floor) else -1 end),
     eta: (.eta_secs // -1), turns}
]
| group_by(.n) | map(last) | sort_by(.n) | .[]
| [.n, .kind, .pct, .eta, .turns] | @tsv
'

main() {
  local input sid="" dir="" common t f c n kind pct eta turns seg line=""
  local -a files
  command -v jq >/dev/null 2>&1 || return 0
  input="$(head -c 1048576)" || return 0
  {
    IFS= read -r -d '' sid
    IFS= read -r -d '' dir
  } < <(jq -j '((.session_id | strings) // "") + "\u0000"
               + ((.workspace.project_dir | strings) // (.workspace.current_dir | strings) // (.cwd | strings) // "")
               + "\u0000"' <<<"$input")
  [[ "$sid" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || return 0
  case "$dir" in /*) ;; *) return 0 ;; esac
  [ -d "$dir" ] || return 0
  common="$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir)" || return 0
  [ -n "$common" ] || return 0
  shopt -s nullglob
  files=("$common"/jikkyo/[1-9]*.json)
  [ "${#files[@]}" -gt 0 ] || return 0
  t="$(now)"
  [[ "$t" =~ ^[0-9]+$ ]] || return 0
  while IFS=$'\t' read -r n kind pct eta turns; do
    # Only checked numbers and the enum state reach the terminal.
    [[ "$n" =~ ^[1-9][0-9]*$ && "$pct" =~ ^-?[0-9]+$ && "$eta" =~ ^-?[0-9]+$ && "$turns" =~ ^[0-9]+$ ]] || continue
    case "$kind" in
      running)
        if [ "$pct" -ge 0 ]; then
          seg="jikkyo #${n} · ${pct}%"
          [ "$eta" -ge 0 ] && seg="${seg} · ~$(fmt_eta "$eta") left"
        elif [ "$turns" = 1 ]; then seg="jikkyo #${n} · 1 turn"
        else seg="jikkyo #${n} · ${turns} turns"; fi ;;
      finished | failed | interrupted | stale) seg="jikkyo #${n} · ${kind}" ;;
      *) continue ;;
    esac
    line="${line:+${line} | }${seg}"
  done < <(for f in "${files[@]}"; do
             # One line per file, `<file name>\t<contents>`, so the name goes
             # with what it holds; a state file is one short line of JSON.
             c=""
             IFS= read -r -d '' c < "$f"
             [ "${#c}" -le 4096 ] || continue
             printf '%s\t%s\n' "${f##*/}" "${c//$'\n'/ }"
           done | jq -n -R -r --arg sid "$sid" --argjson now "$t" --argjson ended_shown "$ENDED_SHOWN" \
               --argjson stale_after "$STALE_AFTER" "$SELECT")
  [ -n "$line" ] && printf '%s\n' "$line"
  return 0
}

# Whatever goes wrong, print nothing rather than break the user's status line.
exec 2>/dev/null
main
exit 0
