#!/bin/bash
# Block `cd`/`pushd` to a directory OUTSIDE the project root. Installed as a PreToolUse hook
# matching the Bash tool (.claude/settings.json).
#
# THE RULE: an agent may cd INTO CHILDREN of the project root (any subdirectory, nested however
# deep) but NEVER into a parent or anywhere outside the root — no `cd ..` past the root, no
# `cd /`, no `cd ~`, no absolute path pointing outside. Letting the working directory leave the
# root is how a session ends up editing the wrong repo or touching another vertical's space.
#
# ALLOWS: cd within the project (cd src, cd ./a/b, nested-then-back-but-still-inside), bare `cd`
# and `cd -`, and — only if explicitly opted in — any dir under CD_ALLOWED_ROOTS (colon-separated;
# unset by default = strict children-only). BLOCKS a cd/pushd whose resolved target is outside.
#
# Parsing + path canonicalization is done in Python (reliable, present here); a pure-bash version
# had normalization holes (a literal '..' wasn't collapsed, so '$ROOT/..' textually passed the
# inside-check). Exit 2 = block, 0 = allow. Fail-safe: unparseable / no python -> allow (the
# dangerous-git hook covers the destructive surface; this hook is specifically about cwd).

INPUT=$(cat)

ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
[ -z "$ROOT" ] && ROOT="$PWD"
ROOT=$(cd "$ROOT" 2>/dev/null && pwd -P) || exit 0

PY=$(command -v python || command -v python3)
[ -z "$PY" ] && exit 0   # no python -> fail-safe allow (can't canonicalize reliably)

RESULT=$(ROOT="$ROOT" ALLOWED="${CD_ALLOWED_ROOTS:-}" EVENT="$INPUT" "$PY" - <<'PYEOF'
import os, sys, json, re

root = os.path.realpath(os.environ["ROOT"])
home = os.path.expanduser("~")
allowed = [root] + [os.path.realpath(p) for p in os.environ.get("ALLOWED", "").split(":") if p]

# The event JSON comes via env (EVENT), NOT stdin — stdin here is the Python script itself
# (the here-doc), so reading stdin would read the script, not the tool event.
try:
    cmd = json.loads(os.environ.get("EVENT", "")).get("tool_input", {}).get("command", "")
except Exception:
    cmd = ""
if not cmd:
    print("ALLOW"); sys.exit(0)

def canon(p):
    # Normalize for comparison on Git-Bash/Windows: forward slashes, collapse .. / .,
    # fold a Windows drive form (C:/x or C:\x) to the Git-Bash mount form (/c/x), and
    # lowercase the drive letter. This makes `cd c:/Code/proj` equal the `/c/Code/proj` root.
    p = p.replace("\\", "/")
    m = re.match(r'^([A-Za-z]):/(.*)$', p)
    if m:
        p = "/" + m.group(1).lower() + "/" + m.group(2)
    p = os.path.normpath(p).replace("\\", "/")
    return p

allowed = [canon(a) for a in allowed]

# HARD DENYLIST — additional paths that must never be reached by filesystem cd.
# A consumer may add their own denylist entries here (absolute paths, canonicalized).
# This denylist is checked FIRST and CANNOT be overridden by CD_ALLOWED_ROOTS.
# By default the list is empty: the root-escape guard above is the primary protection.
DENY = []

def denied(p):
    p = canon(p)
    return any(p == d or p.startswith(d + "/") for d in DENY)

def inside(p):
    p = canon(p)
    if denied(p):
        return False                       # denylist wins over any allow
    return any(p == a or p.startswith(a + "/") for a in allowed)

# Split on shell separators, then find each cd/pushd and its first argument.
segments = re.split(r'[;|&\n]+', cmd)
cd_re = re.compile(r'(?:^|\s)(?:cd|pushd)(?:\s+([^\s;|&]+))?', re.I)

for seg in segments:
    for m in cd_re.finditer(seg):
        arg = m.group(1)
        if arg is None:
            continue                       # bare `cd` -> nav to home-as-root; treat as no-op
        arg = arg.strip().strip('"').strip("'")
        if arg in ("", "-"):
            continue                       # `cd -` previous dir; allow
        if arg == "~" or arg.startswith("~/"):
            cand = home if arg == "~" else os.path.join(home, arg[2:])
        elif arg == "$HOME" or arg.startswith("$HOME/"):
            cand = home if arg == "$HOME" else os.path.join(home, arg[6:])
        elif os.path.isabs(arg):
            cand = arg
        else:
            cand = os.path.join(root, arg)  # relative -> resolve against root
        cand = os.path.normpath(cand)       # collapses .. and . — the canonicalization that matters
        if not inside(cand):
            print("BLOCK\t" + arg)
            sys.exit(0)

print("ALLOW")
PYEOF
)

if [ "${RESULT%%	*}" = "BLOCK" ]; then
  ARG=$(printf '%s' "$RESULT" | cut -f2)
  echo "BLOCKED: 'cd $ARG' would leave the project root ($ROOT). Agents work inside this project: you may cd into CHILDREN of the root, never into a parent or outside it. To READ a file elsewhere use an absolute path with the Read tool instead of cd-ing there. For a legitimate sibling directory (multi-repo workspace) set CD_ALLOWED_ROOTS (colon-separated) in the hook env, or ask the user." >&2
  exit 2
fi

exit 0
