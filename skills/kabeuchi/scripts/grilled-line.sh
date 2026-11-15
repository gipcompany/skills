#!/usr/bin/env bash
#
# grilled-line.sh — put this session's grilled line at the end of a target body.
#
# Usage:
#   grilled-line.sh <timestamp> <tail-key> < body
#
#   timestamp  when the line is written, as `date -Iseconds` prints it:
#              YYYY-MM-DDThh:mm:ss±hh:mm (UTC is +00:00, never Z)
#   tail-key   what the "ready for /goal" check concluded in this session:
#                ready        ready for `/goal`.
#                gaps         not yet ready for `/goal`; see Known gaps.
#                not-ready    not yet ready for `/goal`.
#                not-checked  not checked for `/goal`.
#
# stdin is the body the write-back is about to write: the re-fetched target,
# normalized, with any merge already applied. stdout is that body with every
# existing grilled line removed and the new one put last, ready for the diff.
# The four tails are spelled out here and nowhere else in code, so a caller
# passes a key and can never misspell one.
#
# What counts as an existing grilled line (references/ready-for-goal.md, *The
# grilled line*): a line outside any fenced code block that matches, whole and
# from the first column,
#
#   > Grilled with `/kabeuchi` at <timestamp> — <one of the four tails>
#
# A fence is opened by a line of three or more ` or ~ (indented or not; a
# backtick fence's info string has no backtick) and closed by a line of the
# same character, at least as long, with nothing else on it. A fence that is
# never closed runs to the end of the body. Everything else — an example inside
# a fence, an indented or quoted copy, a line that only resembles it — is
# content and is left exactly as it is.
#
# Each removed line takes the one blank line before it with it (or, at the very
# top of the body, the one after it), so nothing else in the body moves. Then
# trailing blank lines are dropped and the new line is appended after one blank
# line — below any "Known gaps" section, since it is last. Running it twice
# with the same arguments gives the same body.
#
# Output: the body on stdout, normalized (no trailing newline).
#
# Exit codes:
#   0  the body with the new line written to stdout
#   2  bad usage: wrong arguments, an unknown tail key, or a timestamp of the
#      wrong shape (nothing written to stdout)
#
set -uo pipefail
export LC_ALL=C

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NORMALIZE="${HERE}/normalize.sh"

usage() { echo "usage: grilled-line.sh <timestamp> <ready|gaps|not-ready|not-checked> < body" >&2; exit 2; }
die()   { echo "grilled-line.sh: $*" >&2; exit 2; }

[ "$#" -eq 2 ] || usage
ts="$1"; key="$2"

ts_re='^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2}$'
[[ "$ts" =~ $ts_re ]] || die "timestamp must look like 2026-11-15T17:41:59+09:00: $ts"

# The backticks are literal markdown, never command substitution.
# shellcheck disable=SC2016
{
  prefix='> Grilled with `/kabeuchi` at '
  t_ready='ready for `/goal`.'
  t_gaps='not yet ready for `/goal`; see Known gaps.'
  t_not_ready='not yet ready for `/goal`.'
  t_not_checked='not checked for `/goal`.'
}
sep=' — '

case "$key" in
  ready)       tail="$t_ready" ;;
  gaps)        tail="$t_gaps" ;;
  not-ready)   tail="$t_not_ready" ;;
  not-checked) tail="$t_not_checked" ;;
  *)           die "unknown tail key: $key" ;;
esac
new_line="${prefix}${ts}${sep}${tail}"

# is_grilled <line>: exit 0 if the line is a grilled line (whole-line match).
is_grilled() {
  local l="$1" rest stamp
  case "$l" in "$prefix"*) ;; *) return 1 ;; esac
  rest="${l#"$prefix"}"
  stamp="${rest:0:25}"
  [[ "$stamp" =~ $ts_re ]] || return 1
  case "${rest:25}" in
    "${sep}${t_ready}" | "${sep}${t_gaps}" | "${sep}${t_not_ready}" | "${sep}${t_not_checked}") return 0 ;;
  esac
  return 1
}

body="$("$NORMALIZE")" || die "could not normalize the body"

open_re='^[[:space:]]*(`{3,}|~{3,})(.*)$'
close_re='^[[:space:]]*(`{3,}|~{3,})[[:space:]]*$'

out=()           # the lines kept, in order
fence_char=""    # the open fence's character, or empty outside a fence
fence_len=0
skip_blank=0     # a line removed at the very top takes the blank line after it

if [ -n "$body" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    if [ -n "$fence_char" ]; then
      if [[ "$line" =~ $close_re ]]; then
        f="${BASH_REMATCH[1]}"
        if [ "${f:0:1}" = "$fence_char" ] && [ "${#f}" -ge "$fence_len" ]; then
          fence_char=""; fence_len=0
        fi
      fi
      out+=("$line"); continue
    fi
    if [[ "$line" =~ $open_re ]]; then
      f="${BASH_REMATCH[1]}"; info="${BASH_REMATCH[2]}"
      if [ "${f:0:1}" = '~' ] || [[ "$info" != *'`'* ]]; then
        fence_char="${f:0:1}"; fence_len="${#f}"
        skip_blank=0; out+=("$line"); continue
      fi
    fi
    if is_grilled "$line"; then
      n="${#out[@]}"
      if [ "$n" -gt 0 ]; then
        if [ -z "${out[$((n - 1))]}" ]; then unset "out[$((n - 1))]"; fi
      else
        skip_blank=1
      fi
      continue
    fi
    if [ "$skip_blank" -eq 1 ] && [ -z "$line" ]; then skip_blank=0; continue; fi
    skip_blank=0
    out+=("$line")
  done <<<"$body"
fi

# Drop the trailing blank lines, then append the new line after one blank line.
n="${#out[@]}"
while [ "$n" -gt 0 ] && [ -z "${out[$((n - 1))]}" ]; do
  unset "out[$((n - 1))]"; n=$((n - 1))
done

if [ "$n" -gt 0 ]; then
  printf '%s\n' "${out[@]}"
  printf '\n%s' "$new_line"
else
  printf '%s' "$new_line"
fi
