#!/usr/bin/env bash
#
# normalize.sh — canonicalize a markdown body for kabeuchi's change detection.
#
# Usage:
#   normalize.sh [file]      # normalize <file>; with no arg (or '-') read stdin
#
# Emits the normalized body on stdout WITHOUT a trailing newline, so two bodies
# are "the same" iff their normalized bytes are byte-identical (pipe to
# `shasum -a 256` for a cheap equality key). Normalization is:
#
#   - CRLF and lone CR are converted to LF, and
#   - all trailing whitespace (spaces, tabs, newlines) is stripped from the END
#     of the whole body.
#
# This exists because GitHub appends a trailing newline to issue bodies: without
# it, the body you just wrote reads back as an external "conflict" on the very
# next check. Interior content (including blank lines inside the body) is left
# untouched — only the trailing run is trimmed. Normalization is idempotent.
#
# Exit codes:
#   0  normalized body written to stdout
#   2  bad usage (named file does not exist)
#
set -euo pipefail
trap 'echo "normalize.sh: FAILED at line ${LINENO}" >&2' ERR

src="${1:--}"
if [ "$src" = "-" ]; then
  # Append a sentinel so command substitution does not eat real trailing bytes
  # before we get to strip them deliberately.
  raw="$(cat; printf 'x')"
else
  [ -f "$src" ] || { echo "normalize.sh: no such file: $src" >&2; exit 2; }
  raw="$(cat -- "$src"; printf 'x')"
fi
raw="${raw%x}"                     # exact input bytes, trailing newlines intact

raw="${raw//$'\r\n'/$'\n'}"        # CRLF -> LF
raw="${raw//$'\r'/$'\n'}"          # lone CR -> LF

# Strip the trailing whitespace run (space, tab, newline) from the whole body.
while [ -n "$raw" ] && [[ "${raw: -1}" == [[:space:]] ]]; do
  raw="${raw%?}"
done

printf '%s' "$raw"
