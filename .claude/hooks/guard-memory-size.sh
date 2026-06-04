#!/bin/bash
# Memory-file SIZE GUARD. Installed as a PreToolUse hook matching Write|Edit|MultiEdit
# (.claude/settings.json). Keeps any single .claude/memory/*.md file under a soft ceiling
# (~24KB) so memory stays a set of focused, recall-cheap files instead of one bloated blob.
#
# THE BEHAVIOUR THE FOUNDER ASKED FOR — "compress, then continue insertion," not a dumb wall:
# a PreToolUse hook cannot rewrite the file itself (it only allows/blocks the pending write).
# So when a write would push a memory file at/over the ceiling, this hook BLOCKS that one write
# and INSTRUCTS the agent to first COMPRESS/CONSOLIDATE the file's older records (summarize the
# oldest entries, drop superseded detail, or split a topic into its own file + an index line),
# THEN re-issue the write. The net effect is exactly "make room, then continue" — the agent does
# the compaction the hook asks for. A WARN band fires earlier (advisory, never blocks) so the
# agent compacts proactively before it hits the wall.
#
# Scope: ONLY .claude/memory/*.md. Every other file is untouched. Exit 2 = block (with the
# compaction instruction), 0 = allow. Fail-safe: can't determine the path/size -> allow.
#
# Tunables (env): MEMORY_MAX_BYTES (hard ceiling, default 24576 = 24KB),
#                 MEMORY_WARN_BYTES (advisory band, default 20480 = 20KB).

INPUT=$(cat)
MAX="${MEMORY_MAX_BYTES:-24576}"
WARN="${MEMORY_WARN_BYTES:-20480}"

PY=$(command -v python || command -v python3)
[ -z "$PY" ] && exit 0   # no python -> fail-safe allow

# Compute the projected size of the target file AFTER this write, in python (handles Write =
# full replace, and Edit/MultiEdit = old->new delta against the file on disk). Prints:
#   "OK"  |  "WARN\t<path>\t<bytes>"  |  "BLOCK\t<path>\t<bytes>"
RESULT=$(EVENT="$INPUT" MAX="$MAX" WARN="$WARN" "$PY" - <<'PYEOF'
import os, sys, json

try:
    ev = json.loads(os.environ.get("EVENT", ""))
except Exception:
    print("OK"); sys.exit(0)

tool = ev.get("tool_name", "")
ti = ev.get("tool_input", {})
path = ti.get("file_path") or ti.get("path") or ""

# Only police .claude/memory/*.md
norm = path.replace("\\", "/")
if "/.claude/memory/" not in norm or not norm.endswith(".md"):
    print("OK"); sys.exit(0)
# The index file is allowed to be larger (it's a list, not a record store) — but still warn.
is_index = norm.rsplit("/", 1)[-1].upper() == "MEMORY.MD"

def disk_bytes(p):
    try:
        with open(p, "rb") as f: return len(f.read())
    except Exception:
        return 0

# Project the post-write size.
if tool == "Write":
    projected = len(ti.get("content", "").encode("utf-8"))
else:
    # Edit / MultiEdit: start from current size, apply each old->new length delta.
    cur = disk_bytes(path)
    edits = ti.get("edits") or [ti]   # MultiEdit has .edits[]; Edit is a single {old,new}
    delta = 0
    for e in edits:
        old = e.get("old_string", ""); new = e.get("new_string", "")
        n = (1 if e.get("replace_all") else 1)  # count not known w/o reading; assume >=1 occurrence
        delta += (len(new.encode("utf-8")) - len(old.encode("utf-8"))) * 1
    projected = max(0, cur + delta)

MAX = int(os.environ["MAX"]); WARN = int(os.environ["WARN"])
if projected >= MAX and not is_index:
    print(f"BLOCK\t{path}\t{projected}")
elif projected >= WARN:
    print(f"WARN\t{path}\t{projected}")
else:
    print("OK")
PYEOF
)

KIND="${RESULT%%	*}"
P=$(printf '%s' "$RESULT" | cut -f2)
B=$(printf '%s' "$RESULT" | cut -f3)
KB=$(( B / 1024 ))

if [ "$KIND" = "BLOCK" ]; then
  echo "BLOCKED: this write would put '$P' at ~${KB}KB, over the ${MAX}-byte (~$((MAX/1024))KB) memory-file ceiling. Memory must stay a set of focused, recall-cheap files — not one bloated blob. COMPRESS, THEN CONTINUE: (1) consolidate the OLDEST records in this file — summarize them to one line each, drop superseded detail, keep the durable fact; OR (2) split a distinct topic out into its own .claude/memory/<slug>.md and leave a one-line pointer here + a line in MEMORY.md. THEN re-issue your write into the now-smaller file. This is 'make room, then insert', not a hard stop." >&2
  exit 2
fi

if [ "$KIND" = "WARN" ]; then
  echo "[memory-size] '$P' will be ~${KB}KB, nearing the ~$((MAX/1024))KB ceiling. Consider compacting older records or splitting a topic into its own memory file soon — before the next write is blocked. (Advisory; not blocking this write.)" >&2
fi

exit 0
