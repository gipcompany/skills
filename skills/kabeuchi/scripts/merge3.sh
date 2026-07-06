#!/usr/bin/env bash
#
# merge3.sh — conservative 3-way text merge for a kabeuchi write-back.
#
# Usage:
#   merge3.sh <base> <mine> <theirs>
#
#   base   = the last-synced body (the merge base)
#   mine   = the body with your pending edit applied
#   theirs = the current external body (re-fetched right before writing)
#
# Each input is normalized (via normalize.sh) and then merged with
# `git merge-file`, a pure text-merge utility that reads three files and touches
# no repository. All work happens in a private temp dir that is removed on exit,
# so the caller's working tree is never littered (the failure this replaces left
# mine/base/theirs/merged files behind).
#
# Output:
#   The merged body is written to stdout (no trailing newline). On a conflict it
#   contains standard `<<<<<<< ======= >>>>>>>` markers for a human to resolve.
#
# Exit codes:
#   0  clean merge (disjoint changes) — stdout is the integrated body
#   1  conflict (overlapping changes) — stdout carries conflict markers; the
#      caller MUST have a human resolve it, NOT auto-write
#   2  bad usage or an internal git-merge-file fault
#
# Note: `set -e` is intentionally NOT used — a conflict is a non-zero exit from
# git merge-file that this script handles, not a fault.
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NORMALIZE="${HERE}/normalize.sh"

usage() { echo "usage: merge3.sh <base> <mine> <theirs>" >&2; exit 2; }

[ "$#" -eq 3 ] || usage
base="$1"; mine="$2"; theirs="$3"
for f in "$base" "$mine" "$theirs"; do
  [ -f "$f" ] || { echo "merge3.sh: no such file: $f" >&2; exit 2; }
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Normalize each side, then newline-terminate it. git merge-file is line-based;
# a missing final newline can otherwise force a spurious conflict on the last
# line.
for name in base mine theirs; do
  "$NORMALIZE" "${!name}" > "${tmp}/${name}"
  printf '\n' >> "${tmp}/${name}"
done

# git merge-file [current base other]: fold base->other changes into current
# (= mine). -p writes the result to stdout and leaves the files untouched.
merged="$(git merge-file -p "${tmp}/mine" "${tmp}/base" "${tmp}/theirs")" && rc=0 || rc=$?
printf '%s' "$merged"

if [ "$rc" -eq 0 ]; then
  exit 0
elif [ "$rc" -ge 1 ] && [ "$rc" -lt 128 ]; then
  exit 1                                   # rc = number of conflict hunks
else
  echo "merge3.sh: git merge-file failed (rc=${rc})" >&2
  exit 2
fi
