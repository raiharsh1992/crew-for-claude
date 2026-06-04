#!/bin/bash
# PostToolUse advisory hook: emit warn-only nudges for migrations, doc freshness, and test coverage.
# Matcher: 'Write|Edit|MultiEdit'. Never blocks; exits 0 always.
#
# Three nudges, each warn-only, per-session state tracked in temp files:
# (a) migration reminder when a migration-path pattern is touched
#     (route via POST_EDIT_MIGRATION_PATTERN env var, default 'migrations/')
# (b) doc freshness nudge when code files churn but doc target is not touched
#     (route via POST_EDIT_DOC_TARGET env var, default 'CONTEXT.md')
# (c) test-coverage nudge when source files are edited without touching tests
#
# Routing is via env vars (no project-specific path patterns in core).

# Safe temp dir detection (Windows + Unix)
if [ -w "/tmp" ]; then
  TMPDIR="/tmp"
elif [ -w "$TMPDIR" ] 2>/dev/null; then
  : # Use existing TMPDIR
elif [ -n "$TEMP" ] && [ -w "$TEMP" ]; then
  TMPDIR="$TEMP"
elif [ -n "$TMP" ] && [ -w "$TMP" ]; then
  TMPDIR="$TMP"
else
  # Fail gracefully: no writable temp dir, exit 0 (no nudge, no block)
  exit 0
fi

export TMPDIR

# Session key
SESSION_KEY="${CLAUDE_SESSION_ID:-session-$(date +%Y%m%d)}"
NUDGE_STATE_FILE="${TMPDIR}/claude-post-edit-nudges-${SESSION_KEY}.txt"

# Configuration (env vars with defaults)
MIGRATION_PATTERN="${POST_EDIT_MIGRATION_PATTERN:-migrations/}"
DOC_TARGET="${POST_EDIT_DOC_TARGET:-CONTEXT.md}"

# Track the current tool and event
INPUT=$(cat)

# Extract .tool_name (fallback chain; jq not guaranteed on Git Bash)
if command -v jq >/dev/null 2>&1; then
  TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
  FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null)
elif command -v python >/dev/null 2>&1; then
  TOOL_NAME=$(printf '%s' "$INPUT" | python -c 'import sys,json; d=json.load(sys.stdin); print(d.get("tool_name",""))' 2>/dev/null)
  FILE_PATH=$(printf '%s' "$INPUT" | python -c 'import sys,json; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path") or d.get("tool_input",{}).get("notebook_path") or "")' 2>/dev/null)
elif command -v python3 >/dev/null 2>&1; then
  TOOL_NAME=$(printf '%s' "$INPUT" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("tool_name",""))' 2>/dev/null)
  FILE_PATH=$(printf '%s' "$INPUT" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path") or d.get("tool_input",{}).get("notebook_path") or "")' 2>/dev/null)
else
  TOOL_NAME=""
  FILE_PATH=""
fi

# Normalize file path (forward slashes, lowercase for comparison)
FILE_NORM="${FILE_PATH//\\//}"
FILE_LOWER=$(printf '%s' "$FILE_NORM" | tr '[:upper:]' '[:lower:]')
DOC_LOWER=$(printf '%s' "$DOC_TARGET" | tr '[:upper:]' '[:lower:]')

# Only process Write/Edit/MultiEdit
case "$TOOL_NAME" in
  Write|Edit|MultiEdit) ;;
  *) exit 0 ;;
esac

# Initialize nudge state if not present
if [ ! -f "$NUDGE_STATE_FILE" ]; then
  touch "$NUDGE_STATE_FILE"
fi

# (a) Migration reminder: nudge if editing a migration file
MIGRATION_PATTERN_LOWER=$(printf '%s' "$MIGRATION_PATTERN" | tr '[:upper:]' '[:lower:]')
if printf '%s' "$FILE_LOWER" | grep -q "$MIGRATION_PATTERN_LOWER"; then
  # Only emit once per session
  if ! grep -q '^nudged:migrations$' "$NUDGE_STATE_FILE" 2>/dev/null; then
    printf '\n⚠️  Migration file touched: "%s". Verify the migration is idempotent and can roll back.\n\n' "$FILE_PATH" >&2
    printf 'nudged:migrations\n' >> "$NUDGE_STATE_FILE"
  fi
fi

# (b) Doc freshness: nudge if code files churn but doc target is untouched
# Only nudge once per session
if ! grep -q '^nudged:doc$' "$NUDGE_STATE_FILE" 2>/dev/null; then
  # Check if this is a code file (not the doc target, not markdown)
  case "$FILE_LOWER" in
    *'.md'|*"$DOC_LOWER")
      # This is markdown or the doc target itself, skip
      ;;
    *)
      # This is a code file. Check if DOC_TARGET has been touched this session
      if ! grep -q "^edited:$DOC_LOWER$" "$NUDGE_STATE_FILE" 2>/dev/null; then
        printf '\n⚠️  Code file edited: "%s" — but "%s" was not touched.\n' "$FILE_PATH" "$DOC_TARGET" >&2
        printf '    Consider updating "%s" to reflect any contract/API/schema changes.\n\n' "$DOC_TARGET" >&2
        printf 'nudged:doc\n' >> "$NUDGE_STATE_FILE"
      fi
      ;;
  esac
fi

# (c) Test-coverage nudge: nudge if source files are edited without touching tests
if ! grep -q '^nudged:tests$' "$NUDGE_STATE_FILE" 2>/dev/null; then
  case "$FILE_LOWER" in
    *'/test'*|*'/tests'*|*'_test.'*|*'.test.'*|*'_spec.'*|*'.spec.'*)
      # This is a test file, mark it as touched
      printf 'edited:test\n' >> "$NUDGE_STATE_FILE"
      ;;
    *.sh|*.py|*.js|*.ts|*.go|*.rs|*.java|*.kt)
      # This is a source file. Check if any test has been touched
      if ! grep -q '^edited:test$' "$NUDGE_STATE_FILE" 2>/dev/null; then
        printf '\n⚠️  Source file edited: "%s" — consider adding or updating test coverage.\n\n' "$FILE_PATH" >&2
        printf 'nudged:tests\n' >> "$NUDGE_STATE_FILE"
      fi
      ;;
  esac
fi

# Track that this file was touched this session
FILE_HASH=$(printf '%s' "$FILE_PATH" | md5sum 2>/dev/null | cut -d' ' -f1 || printf "$FILE_PATH")
printf 'edited:%s\n' "$FILE_HASH" >> "$NUDGE_STATE_FILE"

# Also track the normalized filename for doc target detection
if [ -n "$FILE_LOWER" ]; then
  printf 'edited:%s\n' "$FILE_LOWER" >> "$NUDGE_STATE_FILE"
fi

exit 0
