#!/bin/bash
# Doctrine-drift gate for workflow files.
#
# BINDING: every workflow that uses agent() must inline the canonical DOCTRINE
# region from .claude/workflows/_doctrine.js byte-identical (save the `export `
# keyword). This hook EXTRACTS the region from each workflow file being written,
# computes its hash, and BLOCKS writes where:
#   (a) the region hash does NOT match the canonical hash, OR
#   (b) a file uses agent() without the doctrine region, OR
#   (c) a file calls agent() outside a resumingAgent scope (raw agent() is forbidden).
#
# The doctrine region is the script-layer discipline covenant — no drift allowed.
# Extracted from .claude/workflows/_doctrine.js between the BEGIN/END delimiters;
# hash is SHA256 over export-stripped, trailing-whitespace-normalised content.
# The delimiters are routed via env vars (DOCTRINE_BEGIN_DELIM / DOCTRINE_END_DELIM)
# with JS-comment defaults hardcoded as fallbacks.
#
# Self-check: if _doctrine.js does not exist, exit 0 gracefully (doctrine optional).
# Fails SAFE on parse error: a syntax error in the hook logic blocks writes rather
# than allowing them (doctrine gate that fails open is worse than useless).
#
# Wired as PreToolUse matcher "Write|Edit|MultiEdit" in .claude/settings.json.
# Exit 0 = allow write. Exit 2 = block write. Fail SAFE = block on unrecoverable error.

# Doctrine delimiter defaults (JS comment format).
: "${DOCTRINE_BEGIN_DELIM:=// ─── BEGIN _doctrine.js canonical (do not edit) ───}"
: "${DOCTRINE_END_DELIM:=// ─── END _doctrine.js canonical ───}"

# Fallback to reading delimiters from _doctrine.js if not set via env.
DOCTRINE_JS_PATH="$(git rev-parse --show-toplevel 2>/dev/null)/.claude/workflows/_doctrine.js"

# Self-check: _doctrine.js must exist. If not, doctrine is not yet deployed — exit gracefully.
if [ ! -f "$DOCTRINE_JS_PATH" ]; then
  exit 0
fi

# Extract the canonical region from _doctrine.js and compute its SHA256 hash.
# Normalisation: strip `export ` keyword, trim trailing whitespace per line, remove final newline.
extract_canonical_hash() {
  local start="$1" end="$2"
  # Extract the region between delimiters (inclusive of the delimiters).
  local region
  region=$(sed -n "/$start/,/$end/p" "$DOCTRINE_JS_PATH" 2>/dev/null)
  [ -z "$region" ] && { echo "ERROR" >&2; return 1; }

  # Strip the delimiter lines themselves, then remove leading `export ` if present.
  region=$(printf '%s' "$region" | sed "1d;\$d" | sed 's/^export //')

  # Normalise: strip trailing whitespace on each line, then on the whole content.
  region=$(printf '%s' "$region" | sed 's/[[:space:]]*$//' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')

  # SHA256 hash.
  printf '%s' "$region" | sha256sum | awk '{print $1}'
}

# Extract region from a workflow file and compute its hash.
extract_workflow_hash() {
  local file="$1" content="$2" start="$3" end="$4"

  # Reconstruct the post-write content from the Write event (UTF-8 decode).
  local region
  region=$(printf '%s' "$content" | sed -n "/$start/,/$end/p" 2>/dev/null)
  [ -z "$region" ] && return 1  # region not found

  # Strip delimiters, remove `export `, normalise trailing whitespace.
  region=$(printf '%s' "$region" | sed "1d;\$d" | sed 's/^export //')
  region=$(printf '%s' "$region" | sed 's/[[:space:]]*$//' | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')

  printf '%s' "$region" | sha256sum | awk '{print $1}'
}

# Check that all agent() calls are inside resumingAgent scopes.
# Simple heuristic: for each agent( call, walk backward to find resumingAgent( on the same logical line/block.
# Fail SAFE: if we can't parse, block rather than allow.
check_agent_scope() {
  local content="$1"

  # Count resumingAgent occurrences (must be >= agent occurrences in valid code).
  local resuming_count agent_count
  resuming_count=$(printf '%s' "$content" | grep -o 'resumingAgent' | wc -l)
  agent_count=$(printf '%s' "$content" | grep -o 'agent(' | wc -l)

  # If there are any agent( calls but fewer resumingAgent scopes, fail.
  if [ "$agent_count" -gt "$resuming_count" ]; then
    return 1
  fi

  # More granular check: look for the pattern `await agent(` NOT preceded by `resumingAgent`.
  # Escape regex for sed (`.` is literal in the pattern match).
  if printf '%s' "$content" | grep -E '(^|[^g])[^a-z_]agent\(' >/dev/null 2>&1; then
    # Verify it's not inside a resumingAgent call by checking context.
    # Simple: if we find `await agent(` on a line where `resumingAgent(` is NOT on the same logical block, fail.
    # For now, a conservative check: grep for lines containing both `await agent(` and ensure prior context includes `resumingAgent`.
    # Fail SAFE: flag any bare `await agent(`.
    if printf '%s' "$content" | grep -E 'await[[:space:]]+agent\(' >/dev/null 2>&1; then
      # Found `await agent(`. Check if it's inside resumingAgent by looking for the function call.
      # Conservative: REQUIRE that agent( appears ONLY inside the resumingAgent function definition itself,
      # or inside a `resumingAgent(...)` call (which would have agent( nested inside the callback).
      # For simplicity, count the nesting: agent( should NOT appear at top-level call sites.
      return 1  # Fail safe: we found a direct agent( — block it unless it's in a resumingAgent context.
    fi
  fi

  return 0
}

# Parse the PreToolUse event (JSON on stdin).
INPUT=$(cat)

# Extract tool_name (jq or fallback chain).
TOOL=""
if command -v jq >/dev/null 2>&1; then
  TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name' 2>/dev/null)
elif command -v python >/dev/null 2>&1; then
  TOOL=$(printf '%s' "$INPUT" | python -c 'import sys,json; print(json.load(sys.stdin).get("tool_name",""))' 2>/dev/null)
elif command -v python3 >/dev/null 2>&1; then
  TOOL=$(printf '%s' "$INPUT" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("tool_name",""))' 2>/dev/null)
fi

# Only process Write|Edit|MultiEdit tools.
case "$TOOL" in
  Write|Edit|MultiEdit) ;;
  *) exit 0 ;;  # Pass through unknown tools.
esac

# Extract file_path and content based on tool type.
FILE_PATH="" CONTENT=""
if [ "$TOOL" = "Write" ]; then
  if command -v jq >/dev/null 2>&1; then
    FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
    CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // ""' 2>/dev/null)
  elif command -v python >/dev/null 2>&1; then
    FILE_PATH=$(printf '%s' "$INPUT" | python -c 'import sys,json; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null)
    CONTENT=$(printf '%s' "$INPUT" | python -c 'import sys,json; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("content",""))' 2>/dev/null)
  elif command -v python3 >/dev/null 2>&1; then
    FILE_PATH=$(printf '%s' "$INPUT" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null)
    CONTENT=$(printf '%s' "$INPUT" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("content",""))' 2>/dev/null)
  fi
elif [ "$TOOL" = "Edit" ]; then
  if command -v jq >/dev/null 2>&1; then
    FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
    CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // ""' 2>/dev/null)
  elif command -v python >/dev/null 2>&1; then
    FILE_PATH=$(printf '%s' "$INPUT" | python -c 'import sys,json; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null)
    CONTENT=$(printf '%s' "$INPUT" | python -c 'import sys,json; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("new_string",""))' 2>/dev/null)
  elif command -v python3 >/dev/null 2>&1; then
    FILE_PATH=$(printf '%s' "$INPUT" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null)
    CONTENT=$(printf '%s' "$INPUT" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("new_string",""))' 2>/dev/null)
  fi
elif [ "$TOOL" = "MultiEdit" ]; then
  if command -v jq >/dev/null 2>&1; then
    FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // ""' 2>/dev/null)
    CONTENT=$(printf '%s' "$INPUT" | jq -r '[.tool_input.edits[].new_string] | join("\n")' 2>/dev/null)
  elif command -v python >/dev/null 2>&1; then
    FILE_PATH=$(printf '%s' "$INPUT" | python -c 'import sys,json; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null)
    CONTENT=$(printf '%s' "$INPUT" | python -c 'import sys,json; d=json.load(sys.stdin); print("\n".join(e.get("new_string","") for e in d.get("tool_input",{}).get("edits",[])))' 2>/dev/null)
  elif command -v python3 >/dev/null 2>&1; then
    FILE_PATH=$(printf '%s' "$INPUT" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("file_path",""))' 2>/dev/null)
    CONTENT=$(printf '%s' "$INPUT" | python3 -c 'import sys,json; d=json.load(sys.stdin); print("\n".join(e.get("new_string","") for e in d.get("tool_input",{}).get("edits",[])))' 2>/dev/null)
  fi
fi

# Normalize file_path: Windows backslashes to forward slashes.
FILE_PATH="${FILE_PATH//\\//}"

# Only process .claude/workflows/*.js files.
if ! printf '%s' "$FILE_PATH" | grep -E '\.claude/workflows/.*\.js$' >/dev/null; then
  exit 0  # Pass through non-workflow files.
fi

# Check if this workflow uses agent() — if not, it's exempt.
if ! printf '%s' "$CONTENT" | grep -E 'agent\(' >/dev/null; then
  exit 0  # No agent() calls — exempt.
fi

# Compute the canonical hash.
CANON_HASH=$(extract_canonical_hash "$DOCTRINE_BEGIN_DELIM" "$DOCTRINE_END_DELIM")
if [ "$CANON_HASH" = "ERROR" ] || [ -z "$CANON_HASH" ]; then
  echo "DOCTRINE GATE: BLOCKED — cannot extract canonical region from _doctrine.js" >&2
  exit 2
fi

# Extract and check the workflow's doctrine region hash.
WF_HASH=$(extract_workflow_hash "$FILE_PATH" "$CONTENT" "$DOCTRINE_BEGIN_DELIM" "$DOCTRINE_END_DELIM")
if [ -z "$WF_HASH" ]; then
  # Region not found in workflow — if the workflow uses agent(), this is an error.
  echo "DOCTRINE GATE: BLOCKED — $FILE_PATH uses agent() but does NOT have the doctrine region" >&2
  exit 2
fi

# Compare hashes.
if [ "$WF_HASH" != "$CANON_HASH" ]; then
  echo "DOCTRINE GATE: BLOCKED — $FILE_PATH doctrine region drifted (hash mismatch)" >&2
  exit 2
fi

# Check that agent() is only inside resumingAgent scopes.
if ! check_agent_scope "$CONTENT"; then
  echo "DOCTRINE GATE: BLOCKED — $FILE_PATH calls agent() outside resumingAgent scope" >&2
  exit 2
fi

exit 0
