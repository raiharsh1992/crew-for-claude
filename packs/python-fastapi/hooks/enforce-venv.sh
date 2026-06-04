#!/bin/bash
# Enforce the project-wide Python venv rule. Ships with the python-fastapi PACK
# (not core) — it only matters where there is Python. Install it as a PreToolUse
# hook matching the Bash tool (.claude/settings.json), alongside
# block-dangerous-git.sh, when this pack is activated.
#
# THE RULE (part of the crew, not a suggestion):
#   The project is tied to ONE virtualenv — `.venv` at the repo root — and EVERY
#   Python command runs inside that venv. Period. No Python touches the system
#   interpreter. This hook makes that rule machine-enforced, not just documented.
#
# It enforces TWO things, PER COMMAND SEGMENT (the command line is split on the
# shell separators && || ; | & and each segment is judged on its own — so a
# trailing comment or a later argument can never mask or trip an earlier check):
#
#   (A) STRUCTURE — a venv may only be created at the canonical path `.venv`.
#       A segment that runs  python/python3/py -m venv <name>, virtualenv <name>,
#       or uv venv <name>  is blocked when <name> is present and is NOT .venv and
#       NOT verify_venv* (the sanctioned CI-equivalence throwaway, gitignored).
#
#   (B) ACTIVATION — a Python package/run command must be venv-scoped. A segment
#       whose command is a bare `pip`, `python`, `pytest`, `mypy`, etc. that does
#       NOT bind to the venv is blocked, because it would hit the system
#       interpreter. A segment is venv-scoped (allowed) if it:
#         • is itself an activation:  source .venv/bin/activate / . .venv/bin/activate
#                             / .venv\Scripts\activate (Windows)
#         • calls the venv tool by path:  .venv/bin/<tool> … / .venv\Scripts\<tool> …
#         • uses a venv-aware runner:  uv run / poetry run / pdm run / hatch run /
#                             pipenv run / tox
#         • OR a PRIOR segment on the same line activated the venv
#                             (source .venv/bin/activate && pytest).
#
# Fail-safe: jq -> python -> python3 -> raw fallback for parsing. If NO parser is
# available, the raw event JSON still contains the command text; the segment scan
# runs over it and OVER-BLOCKS rather than failing open (a Python tool token in
# the raw JSON still trips section B). Exit 2 = block. Exit 0 = allow.
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
  # Parse failed or empty command. Fall back to the raw event text and treat it
  # as unparsed so the scan over-blocks (fail-safe) rather than trusting a clean
  # extraction.
  COMMAND="$INPUT"
  PARSED=0
fi

# ---------------------------------------------------------------------------
# Fail-safe: if NO parser was available (PARSED=0), we are scanning the raw event
# JSON, in which the command's tool token is wrapped in quotes and will NOT sit
# at a segment boundary — so the precise section-B scan below would miss it and
# fail OPEN. Honour the header's promise instead: over-block. If the raw text
# mentions ANY Python tool token at all and is not already clearly venv-scoped,
# block. (This only triggers in the pathological no-jq/no-python environment; a
# python-fastapi repo virtually always has a Python interpreter present.)
# ---------------------------------------------------------------------------
if [ "$PARSED" -eq 0 ]; then
  RAW_PY_RE='(pip3?|python3?|pytest|mypy|flake8|black|isort|bandit|ruff|coverage|uvicorn|gunicorn|alembic|django-admin|virtualenv)'
  if printf '%s' "$COMMAND" | grep -qE "$RAW_PY_RE"; then
    # Allow only if clearly venv-scoped (activation / venv path / runner) in the raw text.
    if printf '%s' "$COMMAND" | grep -qE "${VENV_DIR}[\\\\/]+(bin|Scripts)[\\\\/]+" \
       || printf '%s' "$COMMAND" | grep -qE '(uv[[:space:]]+run|poetry[[:space:]]+run|pdm[[:space:]]+run|hatch[[:space:]]+run|pipenv[[:space:]]+run|tox)' \
       || printf '%s' "$COMMAND" | grep -qE "(source|[[:space:]]\.)[[:space:]]+[^[:space:]]*${VENV_DIR}/(bin|Scripts)/activate"; then
      exit 0
    fi
    echo "BLOCKED (fail-safe): could not parse the hook event with jq/python/python3, and the raw command text mentions a Python tool that may run against the system interpreter. Project rule: every Python command runs inside the '$VENV_DIR' venv. Re-run in an environment with a JSON parser available, or bind the command to the venv explicitly." >&2
    exit 2
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# Split the command line into segments on shell separators: && || ; | & and
# newlines. Each segment is judged independently. We also strip a trailing
# `# comment` from each segment so a comment can neither mask nor trip a check.
# Segments are emitted NUL-free, one per line, via a sentinel replacement.
# ---------------------------------------------------------------------------
SEP=$'\x1f'  # unit-separator sentinel, won't appear in commands
SEGMENTS=$(printf '%s' "$COMMAND" \
  | sed -E "s/(\&\&|\|\||;|\||\&)/${SEP}/g" \
  | tr '\n' "${SEP}" \
  | tr "${SEP}" '\n')

# Did any segment ON THIS LINE activate the venv? (activation persists to later
# segments joined by &&/;). Computed once over all segments.
line_activates_venv() {
  printf '%s' "$COMMAND" | grep -qE "(^|[[:space:]&|;(])(source|\.)[[:space:]]+[^[:space:]]*${VENV_DIR}/(bin|Scripts)/activate" && return 0
  printf '%s' "$COMMAND" | grep -qiE "${VENV_DIR}[\\\\/]+Scripts[\\\\/]+activate" && return 0
  return 1
}
LINE_ACTIVATED=1
line_activates_venv && LINE_ACTIVATED=0   # 0 = true (activated)

block_venv_path() {
  local target="$1"
  echo "BLOCKED: virtualenv created at non-canonical path '$target'. The project convention is a SINGLE venv named '$VENV_DIR' at the repo root. Re-run with '$VENV_DIR' as the target, e.g. 'python -m venv $VENV_DIR'. (The only sanctioned exception is the CI-equivalence throwaway '${VENV_SCRATCH}*', which this hook allows.)" >&2
  exit 2
}

block_system_python() {
  echo "BLOCKED: a Python command in this line would run against the SYSTEM interpreter. Project rule: every Python command runs inside the '$VENV_DIR' venv. Bind it to the venv — e.g. 'source $VENV_DIR/bin/activate && <cmd>' (Windows: '$VENV_DIR\\Scripts\\activate'), call the venv tool by path '$VENV_DIR/bin/<tool>', or use a venv-aware runner like 'uv run'/'poetry run'. (Create the venv with 'python -m venv $VENV_DIR' if it doesn't exist.)" >&2
  exit 2
}

# last_positional <string>: last whitespace-separated token not starting with a
# dash. Operates on a SINGLE segment only (no separators inside), so it can't
# reach across &&/; into another command's arguments.
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

# Is THIS segment venv-scoped on its own? (explicit venv path or a venv-aware
# runner appearing in the segment). Activation of a prior segment is handled
# separately via LINE_ACTIVATED.
segment_is_venv_scoped() {
  local seg="$1"
  printf '%s' "$seg" | grep -qE "${VENV_DIR}[\\\\/]+(bin|Scripts)[\\\\/]+" && return 0
  printf '%s' "$seg" | grep -qE '(^|[[:space:]])(uv[[:space:]]+run|poetry[[:space:]]+run|pdm[[:space:]]+run|hatch[[:space:]]+run|pipenv[[:space:]]+run|tox)([[:space:]]|$)' && return 0
  return 1
}

# A Python tool that, run bare, hits the system interpreter. `python -m venv` is
# handled by section (A) and is NOT a section-(B) violation.
# Leading boundary is COMMAND POSITION within the segment: start of segment (with
# optional leading whitespace) and an optional VAR=val env-prefix. Because each
# segment is already a single command, "start of segment" is the command itself.
PY_TOOL_RE='^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*(pip3?|python3?|py|pytest|mypy|flake8|black|isort|bandit|ruff|coverage|uvicorn|gunicorn|alembic|django-admin)([[:space:]]|$)'

# ---------------------------------------------------------------------------
# Pass 1 — STRUCTURE: any venv-creation segment must target the canonical path.
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

# ---------------------------------------------------------------------------
# Pass 2 — ACTIVATION: any bare Python-tool segment must be venv-scoped, either
# on its own or via a prior activation on the same line.
# ---------------------------------------------------------------------------
while IFS= read -r seg; do
  [ -z "$seg" ] && continue
  seg="${seg%%#*}"                              # strip trailing comment
  seg="$(printf '%s' "$seg" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  [ -z "$seg" ] && continue

  # Only segments whose COMMAND is a Python tool are candidates.
  printf '%s' "$seg" | grep -qE "$PY_TOOL_RE" || continue

  # `python -m venv …` is the sanctioned venv-creation command — governed by (A).
  printf '%s' "$seg" | grep -qE '^[[:space:]]*(python3?|py)[[:space:]]+-m[[:space:]]+venv([[:space:]]|$)' && continue

  # Allowed if this segment is venv-scoped, or the line already activated a venv.
  segment_is_venv_scoped "$seg" && continue
  [ "$LINE_ACTIVATED" -eq 0 ] && continue

  block_system_python
done <<EOF
$SEGMENTS
EOF

exit 0
