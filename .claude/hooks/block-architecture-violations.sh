#!/bin/bash
# Block architecture-violation patterns from being WRITTEN into source code.
# Installed as a PreToolUse hook matching Write|Edit|MultiEdit|NotebookEdit
# (.claude/settings.json). Companion to the secret-patterns system — same
# single-source discipline for architecture rules.
#
# THE PATTERN: the block-architecture-violations hook sources a project's
# custom rules from .claude/hooks/arch-patterns-local.sh (if it exists, your
# project's own rules) and falls back to .claude/hooks/arch-patterns.example.sh
# (the generic template). The ARCH_PATTERNS array defines the violations to
# scan for. The hook extracts the write payload via jq/Python, scans against
# the patterns, and exits 2 (block) if a match is found, or 0 (allow) if clean.
#
# HIGH-CONFIDENCE PATTERNS ONLY: false-positive risk must be near-zero. A
# pattern matching variable names or legitimate library calls is rejected at
# review time. See arch-patterns.example.sh for the inclusion bar.
#
# The sourced pattern file path can be overridden via ARCH_PATTERNS_FILE env var
# (defaults to arch-patterns-local.sh, falling back to arch-patterns.example.sh).
# The scan root directory can be set via ARCH_SCAN_PATHS (defaults to '.').
#
# Fail-safe: identical jq -> python -> python3 -> raw fallback as
# block-secrets-in-writes.sh; if the payload field can't be extracted we scan
# the raw event (over-block, never miss). Exit code 2 = block. Exit code 0 = allow.

INPUT=$(cat)

# --- Determine which pattern file to source ---
# Check for project-local patterns first; if not found, fall back to the example.
# ARCH_PATTERNS_FILE can override the search path (for testing / non-standard layouts).
HOOK_DIR="$(dirname "$0")"
if [ -n "$ARCH_PATTERNS_FILE" ]; then
  PATTERNS_FILE="$ARCH_PATTERNS_FILE"
elif [ -f "$HOOK_DIR/arch-patterns-local.sh" ]; then
  PATTERNS_FILE="$HOOK_DIR/arch-patterns-local.sh"
else
  PATTERNS_FILE="$HOOK_DIR/arch-patterns.example.sh"
fi

# Source the patterns. If the file does not exist and no ARCH_PATTERNS_FILE was set,
# exit 0 gracefully — no patterns defined means no violations to block.
if [ ! -f "$PATTERNS_FILE" ]; then
  exit 0
fi
source "$PATTERNS_FILE" || exit 0

# If ARCH_PATTERNS is empty or not defined, no violations to check.
if [ ${#ARCH_PATTERNS[@]} -eq 0 ]; then
  exit 0
fi

# --- Extract .tool_name (fallback chain; jq not guaranteed on Git Bash) -------
if command -v jq >/dev/null 2>&1; then
  TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name' 2>/dev/null)
elif command -v python >/dev/null 2>&1; then
  TOOL=$(printf '%s' "$INPUT" | python -c 'import sys,json; print(json.load(sys.stdin).get("tool_name",""))' 2>/dev/null)
elif command -v python3 >/dev/null 2>&1; then
  TOOL=$(printf '%s' "$INPUT" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("tool_name",""))' 2>/dev/null)
else
  TOOL=""
fi

# --- Per-tool field selectors -------------------------------------------------
# Choose the jq path-expression for the PAYLOAD field and the FILE-path field
# based on the tool. MultiEdit concatenates every edit's new_string.
case "$TOOL" in
  Write)
    PAYLOAD_JQ='.tool_input.content // ""'
    FILE_JQ='.tool_input.file_path // ""'
    PY_PAYLOAD='print(d.get("tool_input",{}).get("content",""))'
    PY_FILE='print(d.get("tool_input",{}).get("file_path",""))'
    ;;
  Edit)
    PAYLOAD_JQ='.tool_input.new_string // ""'
    FILE_JQ='.tool_input.file_path // ""'
    PY_PAYLOAD='print(d.get("tool_input",{}).get("new_string",""))'
    PY_FILE='print(d.get("tool_input",{}).get("file_path",""))'
    ;;
  MultiEdit)
    PAYLOAD_JQ='[.tool_input.edits[].new_string] | join("\n")'
    FILE_JQ='.tool_input.file_path // ""'
    PY_PAYLOAD='print("\n".join(e.get("new_string","") for e in d.get("tool_input",{}).get("edits",[])))'
    PY_FILE='print(d.get("tool_input",{}).get("file_path",""))'
    ;;
  NotebookEdit)
    PAYLOAD_JQ='.tool_input.new_source // ""'
    FILE_JQ='.tool_input.notebook_path // ""'
    PY_PAYLOAD='print(d.get("tool_input",{}).get("new_source",""))'
    PY_FILE='print(d.get("tool_input",{}).get("notebook_path",""))'
    ;;
  *)
    # Unknown tool (matcher shouldn't route it here, but fail safe): scan the
    # raw event so nothing slips through.
    PAYLOAD_JQ=''
    FILE_JQ=''
    PY_PAYLOAD=''
    PY_FILE=''
    ;;
esac

# --- Extract FILE path (fallback chain) ---------------------------------------
FILE=""
if [ -n "$FILE_JQ" ]; then
  if command -v jq >/dev/null 2>&1; then
    FILE=$(printf '%s' "$INPUT" | jq -r "$FILE_JQ" 2>/dev/null)
  elif command -v python >/dev/null 2>&1; then
    FILE=$(printf '%s' "$INPUT" | python -c "import sys,json; d=json.load(sys.stdin); $PY_FILE" 2>/dev/null)
  elif command -v python3 >/dev/null 2>&1; then
    FILE=$(printf '%s' "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); $PY_FILE" 2>/dev/null)
  fi
fi
if [ "$FILE" = "null" ]; then
  FILE=""
fi

# --- Extract PAYLOAD (fallback chain) -----------------------------------------
PAYLOAD=""
if [ -n "$PAYLOAD_JQ" ]; then
  if command -v jq >/dev/null 2>&1; then
    PAYLOAD=$(printf '%s' "$INPUT" | jq -r "$PAYLOAD_JQ" 2>/dev/null)
  elif command -v python >/dev/null 2>&1; then
    PAYLOAD=$(printf '%s' "$INPUT" | python -c "import sys,json; d=json.load(sys.stdin); $PY_PAYLOAD" 2>/dev/null)
  elif command -v python3 >/dev/null 2>&1; then
    PAYLOAD=$(printf '%s' "$INPUT" | python3 -c "import sys,json; d=json.load(sys.stdin); $PY_PAYLOAD" 2>/dev/null)
  fi
fi

# --- Determine scan scope ---
# ARCH_SCAN_PATHS can be set to limit scans to certain directories (default '.' scans all).
# This is used to focus checks on application code, not test fixtures or vendor directories.
SCAN_PATHS="${ARCH_SCAN_PATHS:-.}"

# --- Union scan — always cover the raw event ---------------------------------
# If payload extraction failed entirely, fall back to raw event only.
# Otherwise, union the extracted payload with the raw event.
if [ -z "$PAYLOAD" ] || [ "$PAYLOAD" = "null" ]; then
  SCAN_TEXT="$INPUT"
else
  SCAN_TEXT="$INPUT"$'\n'"$PAYLOAD"
fi

# --- Scan against all patterns -----------------------------------------------
for pattern in "${ARCH_PATTERNS[@]}"; do
  # Use grep -E (ERE) to match the pattern. Case-sensitive by design.
  # The '--' end-of-options marker prevents patterns beginning with '-' from
  # being interpreted as command-line flags.
  if printf '%s' "$SCAN_TEXT" | grep -E -- "$pattern" >/dev/null 2>&1; then
    {
      echo "BLOCKED: architecture violation detected in write"
      echo "Pattern: $pattern"
      if [ -n "$FILE" ]; then
        echo "File: $FILE"
      fi
      echo ""
      echo "The write contains code that violates your project's architecture rules"
      echo "(defined in $(basename "$PATTERNS_FILE"))."
      echo ""
      echo "To extend or customize these rules, create or edit:"
      echo "  .claude/hooks/arch-patterns-local.sh"
      echo ""
      echo "Add your project-specific patterns there, and this hook will source them"
      echo "automatically. See .claude/hooks/arch-patterns.example.sh for the inclusion"
      echo "bar (lexically unambiguous patterns only; false-positive risk must be"
      echo "near-zero)."
    } >&2
    exit 2
  fi
done

exit 0
