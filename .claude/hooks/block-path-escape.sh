#!/bin/bash
# Block Read/Write/Edit/MultiEdit/NotebookEdit tool use on paths OUTSIDE the project root.
# Installed as a PreToolUse hook matching Read and Write|Edit|MultiEdit|NotebookEdit tools.
#
# THE RULE: an agent may read or write files INSIDE the project root (any subdirectory, nested
# however deep) but NEVER outside — no absolute paths pointing outside the root, no reading
# ~/.bashrc or /etc/passwd from the project context. Letting file operations leave the root
# is how a session ends up modifying the wrong repo or touching another vertical's space.
#
# ALLOWS: file paths within the project (paths relative to root, absolute paths within root),
# and — only if explicitly opted in — any path under PATH_ALLOWED_ROOTS (space or colon-separated;
# unset by default = strict children-only). BLOCKS a Read/Write on a path whose resolved target
# is outside.
#
# Parsing + path canonicalization is done in Python (reliable, present here); a pure-bash version
# had normalization holes (a literal '..' wasn't collapsed, so '$ROOT/..' textually passed the
# inside-check). Exit 2 = block, 0 = allow. Fail-safe: unparseable / no python -> allow (mirrors
# block-cd-escape posture).

INPUT=$(cat)

ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
[ -z "$ROOT" ] && ROOT="$PWD"
ROOT=$(cd "$ROOT" 2>/dev/null && pwd -P) || exit 0

PY=$(command -v python || command -v python3)
[ -z "$PY" ] && exit 0   # no python -> fail-safe allow (can't canonicalize reliably)

RESULT=$(ROOT="$ROOT" ALLOWED="${PATH_ALLOWED_ROOTS:-}" EVENT="$INPUT" "$PY" - <<'PYEOF'
import os, sys, json, re

root = os.path.realpath(os.environ["ROOT"])
home = os.path.expanduser("~")
allowed = [root] + [os.path.realpath(p) for p in os.environ.get("ALLOWED", "").split(":") if p] + \
          [os.path.realpath(p) for p in os.environ.get("ALLOWED", "").split(" ") if p]

# The event JSON comes via env (EVENT), NOT stdin — stdin here is the Python script itself
# (the here-doc), so reading stdin would read the script, not the tool event.
try:
    event = json.loads(os.environ.get("EVENT", ""))
except Exception:
    print("ALLOW"); sys.exit(0)

# Extract file_path from either Read or Write/Edit tool events
file_path = None
try:
    if event.get("tool_name") == "Read":
        file_path = event.get("tool_input", {}).get("file_path")
    elif event.get("tool_name") in ("Write", "Edit", "MultiEdit", "NotebookEdit"):
        file_path = event.get("tool_input", {}).get("file_path")
except Exception:
    pass

if not file_path:
    print("ALLOW"); sys.exit(0)

def canon(p):
    # Normalize for comparison on Git-Bash/Windows: forward slashes, collapse .. / .,
    # fold a Windows drive form (C:/x or C:\x) to the Git-Bash mount form (/c/x), and
    # lowercase the drive letter. This makes `C:/Code/proj` equal the `/c/code/proj` root.
    p = p.replace("\\", "/")
    m = re.match(r'^([A-Za-z]):/(.*)$', p)
    if m:
        p = "/" + m.group(1).lower() + "/" + m.group(2)
    p = os.path.normpath(p).replace("\\", "/")
    return p

allowed = [canon(a) for a in allowed]

def inside(p):
    p = canon(p)
    return any(p == a or p.startswith(a + "/") for a in allowed)

# Resolve the target path: if relative, resolve against root; if absolute, take as-is
if os.path.isabs(file_path):
    cand = file_path
else:
    cand = os.path.join(root, file_path)

cand = os.path.normpath(cand)  # collapses .. and . — the canonicalization that matters

if not inside(cand):
    print("BLOCK\t" + file_path)
    sys.exit(0)

print("ALLOW")
PYEOF
)

if [ "${RESULT%%	*}" = "BLOCK" ]; then
  ARG=$(printf '%s' "$RESULT" | cut -f2)
  echo "BLOCKED: file path '$ARG' would escape the project root ($ROOT). Agents work inside this project: you may read/write files inside the root and its subdirectories, never outside. For a file outside the project (e.g. /tmp, ~/.ssh), set PATH_ALLOWED_ROOTS (space or colon-separated) in the hook env, or ask the user." >&2
  exit 2
fi

exit 0
