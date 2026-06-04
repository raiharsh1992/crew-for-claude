#!/bin/bash
# Enforce the project Python venv STRUCTURE rule. Ships with the python-fastapi PACK
# (not core) — it only matters where there is Python. Install it as a PreToolUse hook
# matching the Bash tool when this pack is activated.
#
# THE RULE (part of the crew convention, not a suggestion):
#   The project maintains ONE canonical Python venv named `.venv` at the repo root.
#   Virtualenv creation commands (python -m venv, virtualenv, uv venv) must target
#   ONLY this canonical path. This hook enforces it machine-wide.
#
# Fail-safe: jq -> python -> python3 -> raw fallback for parsing. If NO parser is
# available, the raw event JSON still contains the command text; the segment scan
# runs over it and OVER-BLOCKS rather than failing open. Exit 2 = block. Exit 0 = allow.
#
# Tunables (optional, via .claude/hooks/hook-globs.env if you source one):
#   VENV_DIR        canonical venv dir name (default ".venv")
#   VENV_SCRATCH    glob prefix for sanctioned throwaway venvs (default "verify_venv")

VENV_DIR="${VENV_DIR:-.venv}"
VENV_SCRATCH="${VENV_SCRATCH:-verify_venv}"

INPUT=$(cat)

# Extract .tool_input.command (fallback chain; jq not guaranteed on Git Bash).
PARSED=1
if command -v jq >/dev/null 2>&1; then
  COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command' 2>/dev/null)
elif command -v python >/dev/null 2>&1; then
  COMMAND=$(printf '%s' "$INPUT" | python -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null)
elif command -v python3 >/dev/null 2>&1; then
  COMMAND=$(printf '%s' "$INPUT" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null)
else
  COMMAND=""
  PARSED=0
fi

if [ -z "$COMMAND" ] || [ "$COMMAND" = "null" ]; then
  # Parse failed or empty command. Fall back to the raw event text.
  COMMAND="$INPUT"
  PARSED=0
fi

# ---------------------------------------------------------------------------
# Fail-safe: if NO parser was available (PARSED=0), we are scanning the raw event
# JSON. Over-block on parse failure rather than failing open.
# ---------------------------------------------------------------------------
if [ "$PARSED" -eq 0 ]; then
  VENV_CREATION_RE='(python3?|py|virtualenv|uv[[:space:]]+venv)'
  if printf '%s' "$COMMAND" | grep -qE "$VENV_CREATION_RE"; then
    # Over-block if we can't parse: require explicit venv path or verify_venv pattern
    if printf '%s' "$COMMAND" | grep -qE "${VENV_DIR}([[:space:]]|$|\")" \
       || printf '%s' "$COMMAND" | grep -qE "${VENV_SCRATCH}"; then
      exit 0
    fi
    echo "BLOCKED (fail-safe): could not parse the hook event with jq/python/python3, and the raw command text mentions a virtualenv-creation command. Project rule: virtualenvs are created at the canonical path '${VENV_DIR}' at the repo root. Re-run in an environment with a JSON parser available." >&2
    exit 2
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# Split the command line into segments on shell separators: && || ; | & and
# newlines. Each segment is judged independently. Strip trailing comments.
# ---------------------------------------------------------------------------
SEP=$'\x1f'  # unit-separator sentinel
SEGMENTS=$(printf '%s' "$COMMAND" \
  | sed -E "s/(\&\&|\|\||;|\||\&)/${SEP}/g" \
  | tr '\n' "${SEP}" \
  | tr "${SEP}" '\n')

block_venv_path() {
  local target="$1"
  echo "BLOCKED: virtualenv created at non-canonical path '$target'. The project convention is a SINGLE venv named '$VENV_DIR' at the repo root. Re-run with '$VENV_DIR' as the target, e.g. 'python -m venv $VENV_DIR'. (The only sanctioned exception is the CI-equivalence throwaway '${VENV_SCRATCH}*', which this hook allows.)" >&2
  exit 2
}

# last_positional <string>: last whitespace-separated token not starting with a dash.
last_positional() {
  local last=""
  for tok in $1; do
    case "$tok" in
      -*) : ;;
      *)  last="$tok" ;;
    esac
  done
  printf '%s' "$last"
}

check_target() {
  local target="$1"
  [ -z "$target" ] && return  # bare invocation — no target, allow (venv errors on its own)
  case "$target" in
    "$VENV_DIR")                      return ;;
    "$VENV_SCRATCH"|"$VENV_SCRATCH"*) return ;;
    *) block_venv_path "$target" ;;
  esac
}

# ---------------------------------------------------------------------------
# STRUCTURE check: any venv-creation segment must target the canonical path.
# ---------------------------------------------------------------------------
while IFS= read -r seg; do
  [ -z "$seg" ] && continue
  seg="${seg%%#*}"                              # strip trailing comment
  seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  [ -z "$seg" ] && continue

  if printf '%s' "$seg" | grep -qE '^[[:space:]]*(python3?|py)[[:space:]]+-m[[:space:]]+venv([[:space:]]|$)'; then
    SUFFIX=$(printf '%s' "$seg" | sed -E 's/^[[:space:]]*[^ ]+[[:space:]]+-m[[:space:]]+venv[[:space:]]*//')
    check_target "$(last_positional "$SUFFIX")"
  elif printf '%s' "$seg" | grep -qE '^[[:space:]]*virtualenv([[:space:]]|$)'; then
    SUFFIX=$(printf '%s' "$seg" | sed -E 's/^[[:space:]]*virtualenv[[:space:]]*//')
    check_target "$(last_positional "$SUFFIX")"
  elif printf '%s' "$seg" | grep -qE '^[[:space:]]*uv[[:space:]]+venv([[:space:]]|$)'; then
    SUFFIX=$(printf '%s' "$seg" | sed -E 's/^[[:space:]]*uv[[:space:]]+venv[[:space:]]*//')
    check_target "$(last_positional "$SUFFIX")"
  fi
done <<EOF
$SEGMENTS
EOF

exit 0
