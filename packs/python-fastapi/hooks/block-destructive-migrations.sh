#!/bin/bash
# Block irreversible Python-stack database migrations. Ships with the
# python-fastapi PACK (not core) — `alembic` is Python/SQLAlchemy-specific, so the
# rule lives here rather than in the language-neutral core git guard. Install as a
# PreToolUse hook matching the Bash tool when this pack is activated.
#
# Blocks:  alembic downgrade base   (drops every migration — destroys schema state)
#          alembic downgrade -<n>   / alembic downgrade - (relative rollback)
# Allows:  alembic upgrade …, alembic downgrade <specific-revision> (a forward-or-
#          targeted move is recoverable; `base`/relative rollback is the dangerous one).
#
# Fail-safe: same jq -> python -> python3 -> raw fallback as the other hooks;
# over-blocks on parse failure (the raw event still contains the command text),
# never fails open. Exit 2 = block. Exit 0 = allow.

INPUT=$(cat)

if command -v jq >/dev/null 2>&1; then
  COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command' 2>/dev/null)
elif command -v python >/dev/null 2>&1; then
  COMMAND=$(printf '%s' "$INPUT" | python -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null)
elif command -v python3 >/dev/null 2>&1; then
  COMMAND=$(printf '%s' "$INPUT" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null)
else
  COMMAND=""
fi

if [ -z "$COMMAND" ] || [ "$COMMAND" = "null" ]; then
  COMMAND="$INPUT"   # raw fallback — substring match below still fires (over-block)
fi

if printf '%s' "$COMMAND" | grep -qiE 'alembic[[:space:]]+downgrade[[:space:]]+(base|-)'; then
  echo "BLOCKED: 'alembic downgrade base' (or a relative downgrade) destroys migration/schema state irreversibly. This is a python-pack backstop. The user has NOT authorized it — STOP and ask. A targeted downgrade to a specific revision (alembic downgrade <rev>) is allowed; 'base' and relative rollbacks are not." >&2
  exit 2
fi

exit 0
