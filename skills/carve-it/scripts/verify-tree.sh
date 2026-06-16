#!/usr/bin/env bash
#
# verify-tree.sh — the tree-equivalence gate for a carve-it rewrite.
#
# Usage:
#   verify-tree.sh <target-commit> <constructed-tip>
#
# Asserts that the two commit-ish resolve to the SAME tree object, i.e. that the
# carved sequence reproduces the target commit's content byte-for-byte. This is
# the safety gate that lets carve-it skip a full re-test: if the trees match and
# the original commit was green, the final commit is green too.
#
# Exit codes:
#   0  trees identical
#   1  trees differ (a diff was dropped or duplicated) — caller MUST abort
#   2  bad usage
#
# A mismatch is a normal verification outcome, so it exits 1 cleanly WITHOUT the
# ERR trap firing (the trap is for genuine script faults only).
#
set -euo pipefail
trap 'echo "verify-tree.sh: FAILED at line ${LINENO}" >&2' ERR

if [ "$#" -ne 2 ]; then
  echo "usage: verify-tree.sh <target-commit> <constructed-tip>" >&2
  exit 2
fi

target="$1"
tip="$2"

target_tree="$(git rev-parse --verify "${target}^{tree}")"
tip_tree="$(git rev-parse --verify "${tip}^{tree}")"

if [ "${target_tree}" = "${tip_tree}" ]; then
  echo "OK: trees identical (${target_tree})"
  exit 0
fi

{
  echo "MISMATCH: tree-equivalence gate FAILED"
  echo "  target ${target} -> ${target_tree}"
  echo "  tip    ${tip} -> ${tip_tree}"
  echo "  differing paths (target..tip):"
  git diff --stat "${target}" "${tip}" || true
} >&2
exit 1
