#!/usr/bin/env bash
# verify-workflow.sh — the FAITHFUL syntax check for a Workflow script (.claude/workflows/*.js).
#
# Why this exists (see crew issue #12): workflow scripts carry BOTH `export const meta`
# (ESM-only) AND top-level `return` early-abort guards (CommonJS/function-scope only,
# ILLEGAL in ESM). Stock Node has no mode that models the runtime's actual wrapper:
#   - `node --check file.js`                 → PASSES but silently ignores `export` (false green)
#   - `node --input-type=module --check`     → FAILS "Illegal return statement" (false red)
# The Workflow runtime wraps the body in an async-function-with-exports context that allows
# both. This helper models that: strip the leading `export ` keyword and wrap the body in an
# async function, then `node --check`. Exit 0 = the script is syntactically valid for the
# runtime; non-zero = a real syntax error.
#
# Usage: verify-workflow.sh path/to/workflow.js
set -euo pipefail
f="${1:?usage: verify-workflow.sh <workflow.js>}"
[ -f "$f" ] || { echo "verify-workflow: no such file: $f" >&2; exit 2; }
# Strip leading `export ` (so top-level return is inside the fn) and wrap; check as a script.
{ printf '(async function(){\n'; sed 's/^export //' "$f"; printf '\n})()\n'; } | node --check - \
  && echo "verify-workflow: OK ($f is valid for the workflow runtime)"
