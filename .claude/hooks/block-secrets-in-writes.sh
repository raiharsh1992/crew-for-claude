#!/bin/bash
# Block a real secret from being WRITTEN into a tracked source/config file.
# Installed as a PreToolUse hook matching Write|Edit|MultiEdit|NotebookEdit
# (.claude/settings.json). Companion to block-dangerous-git.sh, which covers the
# Bash surface. Both source secret-patterns.sh, so the credential-shape list and
# the scanning logic are single-sourced — the two surfaces can never drift.
#
# THE GAP THIS CLOSES: the Bash hook scans only `.tool_input.command`. An agent
# that writes a real secret into a source file / config / Dockerfile / CI workflow
# via the Write/Edit/MultiEdit/NotebookEdit tool bypassed it entirely — caught
# only later by human review or .gitignore. This makes it a HARD machine gate at
# write-time.
#
# Sanctioned-secret-file exemption: writes into a gitignored secret-bearing file
# (.env / .pem / .key / credentials.json / .secret) are allowed — that is the ONE
# sanctioned path for a real local secret, and .gitignore already guarantees the
# file never reaches git. *.env.example is the inverse: it IS tracked, so it gets
# NO exemption and is scanned at full strength (a placeholder passes the
# high-confidence shapes; a real secret correctly trips). The exemption fails
# CLOSED toward scanning: a path we can't extract is treated as "not exempt" and
# scanned.
#
# Fail-safe: identical jq -> python -> python3 -> raw fallback as the Bash hook;
# if the payload field can't be extracted we scan the raw event (over-block,
# never miss). Exit code 2 = block. Exit code 0 = allow.

# Single source of truth for credential-shape detection + scan_for_secrets.
source "$(dirname "$0")/secret-patterns.sh"

INPUT=$(cat)

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

# --- Path exemption (fails CLOSED toward scanning) ----------------------------
# The exemption is matched against the BASENAME only, anchored exactly as
# .gitignore grants — `.env` (exact) or `.env.*` (dot-env with any suffix).
# Unanchored suffix globs like *.env / *.env.* are dropped so tracked files like
# `production.env`, `config.env.py`, `app/mycredentials.json` are NOT exempted.
# Order is load-bearing: *.example is matched FIRST and forced down the scanned
# path, so .env.example is NEVER wrongly exempted by the basename rule below.
# Only a positive match against a SUCCESSFULLY extracted path grants the
# exemption; an empty/unextractable FILE falls through to scanning.
# basename — the anchor for all exemption tests. Normalize Windows backslashes to
# forward slashes FIRST: the IDE passes `c:\…\foo.env` on Windows, and a bare
# `${FILE##*/}` would not strip a backslash path, leaving BASE = the whole path so
# NO exemption (incl. .env/.pem) would ever match. Strip both separators.
FILE_NORM="${FILE//\\//}"
BASE="${FILE_NORM##*/}"
case "$BASE" in
  *.example)
    : # tracked placeholder file — DO NOT exempt; scan at full strength
    ;;
  secret-patterns.sh)
    exit 0  # the credential-shape SSOT itself — it MUST contain example secret
            # shapes (the detection patterns + the test-fixture allowlist), so
            # scanning it at full strength would make the one file the crew can
            # never edit through its own write hook. Exempt by exact basename.
    ;;
  .env)
    exit 0  # exact .env — sanctioned gitignored secret-bearing file
    ;;
  .env.*)
    exit 0  # .env.local, .env.production, etc.
    ;;
  *.pem|*.key|credentials.json|*.secret)
    exit 0  # other sanctioned gitignored secret-bearing files
    ;;
esac

# --- Union scan — always cover the raw event ---------------------------------
# A non-string `content` (int/bool/list) leaves PAYLOAD non-empty (e.g. "123")
# so a naive empty/null fail-safe would never fire and a secret elsewhere in the
# event (e.g. in file_path, or any other field) would be silently missed.
# Solution: ALWAYS scan BOTH the raw event AND the extracted payload. The union
# is formed by concatenating them. The path-exemption above already short-
# circuits (exit 0) for sanctioned .env paths BEFORE we reach here, so the
# .env sanctioned workflow does not regress — the exemption fires first.
# If payload extraction failed entirely, fall back to raw event only (the
# original fail-safe is preserved inside the union).
if [ -z "$PAYLOAD" ] || [ "$PAYLOAD" = "null" ]; then
  PAYLOAD="$INPUT"
else
  PAYLOAD="$INPUT"$'\n'"$PAYLOAD"
fi

# --- Scan -----------------------------------------------------------------------
if scan_for_secrets "$PAYLOAD" >/dev/null; then
  echo "$SECRET_BLOCK_MSG" >&2
  exit 2
fi

exit 0
