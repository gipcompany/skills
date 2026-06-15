#!/usr/bin/env bash
#
# scenario.sh — the end-to-end sample INPUT for carve-it's tests.
#
# Sourced by run.sh. `mk_target_repo` builds a throwaway git repo whose branch
# 'work' holds ONE target commit: the sample input a carve operates on. That
# commit deliberately entangles two intents inside src/app.js —
#
#   - a pure rename  fmt -> format        (refactor, behavior-preserving)
#   - a new `.trim()` behavior + its test (feat, behavior-changing)
#
# so the documented split is TWO commits, and src/app.js is the file that is
# "split across multiple commits" (Phase 3). run.sh reconstructs that split with
# only the documented staging moves and asserts the tree-equivalence gate, fixing
# the expected output: a correct carve passes (exit 0), a carve that drops
# app.js's final-state checkout fails (exit 1).
#
# Echoes the repo path on stdout; the caller is responsible for removing it.

mk_target_repo() {
  local d
  d="$(mktemp -d)"
  git -C "$d" init -q -b work
  git -C "$d" config user.email carve@test
  git -C "$d" config user.name carve-test
  mkdir -p "$d/src" "$d/test"

  # --- baseline commit: symbol is named `fmt`, run() does not trim ---
  cat > "$d/src/format.js" <<'EOF'
function fmt(x) {
  return String(x)
}
module.exports = { fmt }
EOF
  cat > "$d/src/app.js" <<'EOF'
const { fmt } = require('./format')
function run(x) {
  return fmt(x)
}
module.exports = { run }
EOF
  git -C "$d" add -A
  git -C "$d" commit -q -m 'chore: baseline'

  # --- target commit: rename fmt->format (refactor) + trim + its test (feat) ---
  cat > "$d/src/format.js" <<'EOF'
function format(x) {
  return String(x)
}
module.exports = { format }
EOF
  cat > "$d/src/app.js" <<'EOF'
const { format } = require('./format')
function run(x) {
  return format(x).trim()
}
module.exports = { run }
EOF
  cat > "$d/test/app.test.js" <<'EOF'
const { run } = require('../src/app')
if (run('  hi  ') !== 'hi') throw new Error('run() should trim')
EOF
  git -C "$d" add -A
  git -C "$d" commit -q -m 'feat: trim run() output and rename fmt to format'

  echo "$d"
}

# Write src/app.js in its INTERMEDIATE state: renamed to `format`, but without
# the `.trim()` behavior yet. This is the one direct-edit staging move the carve
# uses for the split file (Phase 3); every other file reaches its final state via
# `git checkout <target> -- <file>`.
write_app_intermediate() {
  cat > "$1/src/app.js" <<'EOF'
const { format } = require('./format')
function run(x) {
  return format(x)
}
module.exports = { run }
EOF
}
