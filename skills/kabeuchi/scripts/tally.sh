#!/usr/bin/env bash
#
# tally.sh — count a kabeuchi vote and build the 🗳️ line shown under ➡️.
#
# Usage:
#   tally.sh [file]      # read the votes from <file>; with no file (or '-')
#                        # read stdin
#
# Grouping three free-text answers into "the same option" is a judgement call,
# so kabeuchi does that itself and hands this script the result. Everything
# after the grouping is a fixed rule that has to be applied identically on every
# question of a session that runs for dozens of turns, which is why it lives in
# a script with tests instead of in prose the model re-reads.
#
# Input: exactly three lines, one per voter, tab-separated:
#
#   <perspective> TAB <option-id> TAB <state>
#
#   perspective  the voter's label as it should appear on screen (e.g. `spec`,
#                `code`, `docs`); any text without tabs or control characters
#   option-id    the option the voter chose, after grouping — [A-Za-z0-9_-]+ —
#                or `-` for a vote that names no option (abstain, failed)
#   state        what became of the vote:
#                  valid       the verifier upheld its evidence
#                  invalid     the verifier rejected its evidence
#                  abstain     the voter found no evidence from its perspective
#                  failed      the voter failed twice (once plus one retry)
#                  unverified  the verifier failed twice, so nothing was checked
#
# Rules (the agreed spec — references/voting.md explains the why):
#
#   - abstain and failed count as neither valid nor invalid
#   - an option needs at least 2 valid votes to become the recommendation; that
#     threshold does not drop when some voters abstain or fail
#   - if any vote is unverified, nothing is recommended: votes whose evidence
#     was never checked must not pass as a vetted recommendation. The verifier
#     judges all three votes in one pass, so unverified never appears next to
#     valid or invalid; that combination is rejected as malformed input
#
# Output: two lines on stdout.
#
#   recommend<TAB><option-id>     the winning option, or `-` for "do not narrow
#                                 to one; lay the competing options side by side"
#   🗳️ ...                         the line to print directly under ➡️
#
# In the 🗳️ line, N/M reads "N votes for the recommendation out of M votes that
# were judged" (valid + invalid). Abstained and failed votes are not judged, so
# they are left out of M and named in the parentheses instead.
#
# Exit codes:
#   0  tallied; both lines written to stdout
#   2  bad usage or malformed input (nothing written to stdout)
#
set -uo pipefail

usage() { echo "usage: tally.sh [file]" >&2; exit 2; }
die()   { echo "tally.sh: $*" >&2; exit 2; }

[ "$#" -le 1 ] || usage
src="${1:--}"
case "$src" in -) ;; -*) usage ;; esac

if [ "$src" = "-" ]; then
  input="$(cat)"
else
  [ -f "$src" ] || die "no such file: $src"
  input="$(cat -- "$src")"
fi

# Parallel indexed arrays rather than an associative array: macOS still ships
# bash 3.2, which has no `declare -A`.
persp=(); opt=(); state=()
n=0
while IFS= read -r line || [ -n "$line" ]; do
  line="${line%$'\r'}"
  [ -n "$line" ] || continue
  IFS=$'\t' read -r p o s extra <<< "$line"
  [ -z "${extra:-}" ] || die "line $((n + 1)): expected 3 tab-separated fields"
  if [ -z "${p:-}" ] || [ -z "${o:-}" ] || [ -z "${s:-}" ]; then
    die "line $((n + 1)): expected 3 tab-separated fields"
  fi
  case "$p" in *[[:cntrl:]]*) die "line $((n + 1)): control character in perspective" ;; esac
  case "$s" in
    valid|invalid|unverified)
      case "$o" in -|*[!A-Za-z0-9_-]*) die "line $((n + 1)): state $s needs an option id ([A-Za-z0-9_-]+)" ;; esac ;;
    abstain|failed)
      [ "$o" = "-" ] || die "line $((n + 1)): state $s takes option id '-'" ;;
    *) die "line $((n + 1)): unknown state: $s" ;;
  esac
  persp+=("$p"); opt+=("$o"); state+=("$s")
  n=$((n + 1))
done <<< "$input"

[ "$n" -eq 3 ] || die "expected exactly 3 votes, got $n"

# The verifier checks all three votes in one pass, so if it failed, no vote was
# judged: a valid or invalid state next to an unverified one is a caller bug.
case " ${state[*]} " in
  *" unverified "*)
    case " ${state[*]} " in *" valid "*|*" invalid "*)
      die "unverified cannot be mixed with valid or invalid (the verifier judges all votes at once)" ;;
    esac ;;
esac

# --- decide -----------------------------------------------------------------

winner=-
unverified=0
judged=0
valid=0
for i in 0 1 2; do
  case "${state[$i]}" in
    unverified) unverified=1 ;;
    valid)      judged=$((judged + 1)); valid=$((valid + 1)) ;;
    invalid)    judged=$((judged + 1)) ;;
  esac
done

if [ "$unverified" -eq 0 ]; then
  for i in 0 1 2; do
    [ "${state[$i]}" = valid ] || continue
    c=0
    for j in 0 1 2; do
      [ "${state[$j]}" = valid ] && [ "${opt[$j]}" = "${opt[$i]}" ] && c=$((c + 1))
    done
    if [ "$c" -ge 2 ]; then winner="${opt[$i]}"; wins="$c"; break; fi
  done
fi

# --- render -----------------------------------------------------------------

# note <index> — describe one vote for the parenthesised list. A valid vote for
# the winner is not mentioned (the head of the line already counts it).
note() {
  local p="${persp[$1]}" o="${opt[$1]}" s="${state[$1]}"
  case "$s" in
    valid)      if [ "$winner" = - ]; then printf '%s: %s' "$p" "$o"; else printf '%s: chose %s instead' "$p" "$o"; fi ;;
    invalid)    printf '%s: invalid, evidence did not hold' "$p" ;;
    abstain)    printf '%s: abstained' "$p" ;;
    failed)     printf '%s: failed' "$p" ;;
    unverified) printf '%s: %s (unverified)' "$p" "$o" ;;
  esac
}

notes=""
for i in 0 1 2; do
  [ "${state[$i]}" = valid ] && [ "${opt[$i]}" = "$winner" ] && continue
  [ -z "$notes" ] || notes+="; "
  notes+="$(note "$i")"
done

if [ "$winner" != - ]; then
  if [ "$wins" -eq "$valid" ]; then head="${wins}/${judged} valid, unanimous"; else head="${wins}/${judged} valid, majority"; fi
elif [ "$unverified" -eq 1 ]; then
  head="no recommendation, unverified because the verifier failed"
elif [ "$valid" -eq 0 ]; then
  head="no recommendation, no valid votes"
elif [ "$valid" -eq 1 ]; then
  head="no recommendation, only 1 valid vote"
else
  head="no recommendation, valid votes split"
fi
[ -z "$notes" ] || head+=" (${notes})"

printf 'recommend\t%s\n' "$winner"
printf '🗳️ %s\n' "$head"
