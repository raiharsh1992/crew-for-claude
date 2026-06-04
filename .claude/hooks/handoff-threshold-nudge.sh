#!/bin/bash
# PostToolUse advisory hook: nudge toward /context-handoff at call/edit thresholds.
# Matcher: '.*' (all tools). Never blocks; exits 0 always.
#
# Counts tool calls and file edits per session using temp files keyed by
# $CLAUDE_SESSION_ID (fallback: date-based per-day key if unset). Emits a LOUD
# once-per-band nudge to invoke /context-handoff at thresholds.
#
# Thresholds: route via env vars HANDOFF_CALL_THRESHOLD (default 50) and
# HANDOFF_EDIT_THRESHOLD (default 30).
#
# Temp-file naming: uses 'claude-handoff-counter' prefix (neutral, generic).
# Fails gracefully if /tmp is unwritable.

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

# Session key: use CLAUDE_SESSION_ID if set, else use a date-based per-day key
SESSION_KEY="${CLAUDE_SESSION_ID:-session-$(date +%Y%m%d)}"
COUNTER_FILE="${TMPDIR}/claude-handoff-counter-${SESSION_KEY}.txt"
NUDGE_FILE="${TMPDIR}/claude-handoff-nudge-${SESSION_KEY}.txt"

# Thresholds (configurable via env vars)
CALL_THRESHOLD="${HANDOFF_CALL_THRESHOLD:-50}"
EDIT_THRESHOLD="${HANDOFF_EDIT_THRESHOLD:-30}"

# Track the current tool and event
INPUT=$(cat)

# Extract .tool_name (fallback chain; jq not guaranteed on Git Bash)
if command -v jq >/dev/null 2>&1; then
  TOOL_NAME=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
elif command -v python >/dev/null 2>&1; then
  TOOL_NAME=$(printf '%s' "$INPUT" | python -c 'import sys,json; print(json.load(sys.stdin).get("tool_name",""))' 2>/dev/null)
elif command -v python3 >/dev/null 2>&1; then
  TOOL_NAME=$(printf '%s' "$INPUT" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("tool_name",""))' 2>/dev/null)
else
  TOOL_NAME=""
fi

# Increment call counter
CALL_COUNT=0
if [ -f "$COUNTER_FILE" ]; then
  CALL_COUNT=$(grep -c '^call$' "$COUNTER_FILE" 2>/dev/null)
  [ -z "$CALL_COUNT" ] && CALL_COUNT=0
fi
CALL_COUNT=$((CALL_COUNT + 1))
printf 'call\n' >> "$COUNTER_FILE"

# Count file edits (Write, Edit, MultiEdit tools modify files)
case "$TOOL_NAME" in
  Write|Edit|MultiEdit)
    printf 'edit\n' >> "$COUNTER_FILE"
    ;;
esac

# Count current edits
EDIT_COUNT=0
if [ -f "$COUNTER_FILE" ]; then
  EDIT_COUNT=$(grep -c '^edit$' "$COUNTER_FILE" 2>/dev/null)
  [ -z "$EDIT_COUNT" ] && EDIT_COUNT=0
fi

# Check if we should emit a nudge (once per band, tracked via nudge file)
if [ ! -f "$NUDGE_FILE" ]; then
  NUDGE_EMITTED=''
else
  NUDGE_EMITTED=$(cat "$NUDGE_FILE")
fi

# Emit nudge for call threshold (once)
if [ "$CALL_COUNT" -ge "$CALL_THRESHOLD" ] && ! printf '%s' "$NUDGE_EMITTED" | grep -q 'calls'; then
  printf '
████████████████████████████████████████████████████████████████████████████
  HANDOFF NUDGE: %d tool calls so far — consider invoking /context-handoff
  to clear the session work area and continue with a fresh context.
████████████████████████████████████████████████████████████████████████████
' "$CALL_COUNT" >&2
  printf '%s,calls' "$NUDGE_EMITTED" >> "$NUDGE_FILE"
fi

# Emit nudge for edit threshold (once)
if [ "$EDIT_COUNT" -ge "$EDIT_THRESHOLD" ] && ! printf '%s' "$NUDGE_EMITTED" | grep -q 'edits'; then
  printf '
████████████████████████████████████████████████████████████████████████████
  HANDOFF NUDGE: %d file edits so far — consider invoking /context-handoff
  to clear the session work area and continue with a fresh context.
████████████████████████████████████████████████████████████████████████████
' "$EDIT_COUNT" >&2
  printf '%s,edits' "$NUDGE_EMITTED" >> "$NUDGE_FILE"
fi

exit 0
