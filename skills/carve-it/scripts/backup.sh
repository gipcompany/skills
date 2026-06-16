#!/usr/bin/env bash
#
# backup.sh — create a timestamped backup branch before a carve-it rewrite.
#
# Usage:
#   backup.sh [branch]
#
# With no argument the current branch is used. Creates a ref of the form
#   backup/<branch>/<YYYYMMDD-HHMMSS>
# pointing at <branch>'s current tip, and prints that ref name to stdout so the
# caller can record it. Never moves or deletes anything; creation only.
#
set -euo pipefail
trap 'echo "backup.sh: FAILED at line ${LINENO}" >&2' ERR

branch="${1:-$(git symbolic-ref --short HEAD)}"

# Refuse to proceed if the branch does not resolve to a commit (e.g. detached
# HEAD with no argument, or a typo'd branch name).
git rev-parse --verify --quiet "${branch}^{commit}" >/dev/null || {
  echo "backup.sh: '${branch}' is not a valid branch/commit" >&2
  exit 1
}

ts="$(date +%Y%m%d-%H%M%S)"
ref="backup/${branch}/${ts}"

if git rev-parse --verify --quiet "refs/heads/${ref}" >/dev/null; then
  echo "backup.sh: '${ref}' already exists; refusing to overwrite" >&2
  exit 1
fi

git branch "${ref}" "${branch}"
echo "${ref}"
