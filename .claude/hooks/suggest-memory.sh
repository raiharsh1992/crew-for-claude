#!/bin/bash
# Learning-loop SENSOR. Installed as a Stop hook (.claude/settings.json). Fires when
# the main agent finishes a turn. Its only job is to NOTICE that the turn contained a
# learnable moment — a correction, a "from now on", a locked decision, a stated
# preference — and SURFACE a one-line nudge to run /remember. It NEVER writes anything
# and NEVER blocks. It is the capture half of the loop; /remember is the write half.
#
# WHY A HOOK AND NOT THE AGENT'S JUDGEMENT: the agent that just got corrected is the
# least reliable narrator of "I should remember that" — it's mid-flow, optimising for
# finishing the task, and the lesson dies with its context window. A deterministic
# sensor on the transcript catches the moment every time, for free, regardless of which
# model ran the turn.
#
# DESIGN CONSTRAINTS:
#   - Stop hooks get {transcript_path, ...} on stdin. We read the LAST user message
#     from the transcript and pattern-match it. Cheap, deterministic, no model call.
#   - Output a nudge by exiting 0 with a message on stdout (additionalContext). We do
#     NOT use exit 2 (block) — a learnable moment is not a reason to stop the agent.
#   - Fail SILENT, never noisy: if we can't parse the transcript, we emit nothing. A
#     missed nudge is fine (the user can always run /remember by hand); a spurious
#     nudge on every turn would train the user to ignore it. Precision > recall here.
#   - Loop guard: if the stop event is itself the result of a prior stop-hook
#     continuation (stop_hook_active=true), do nothing — never recurse.
#
# Exit 0 always. Output (if any) is an advisory nudge, not a control signal.

INPUT=$(cat)

# --- extract transcript_path and stop_hook_active (jq -> python -> bail) ---
extract() {  # $1 = jq filter, $2 = python keypath expression
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$INPUT" | jq -r "$1" 2>/dev/null
  elif command -v python >/dev/null 2>&1; then
    printf '%s' "$INPUT" | python -c "import sys,json;d=json.load(sys.stdin);print($2)" 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$INPUT" | python3 -c "import sys,json;d=json.load(sys.stdin);print($2)" 2>/dev/null
  else
    printf ''
  fi
}

STOP_ACTIVE=$(extract '.stop_hook_active' 'd.get("stop_hook_active",False)')
case "$STOP_ACTIVE" in
  true|True|1) exit 0 ;;   # never recurse on our own continuation
esac

TRANSCRIPT=$(extract '.transcript_path' 'd.get("transcript_path","")')
[ -z "$TRANSCRIPT" ] || [ ! -f "$TRANSCRIPT" ] && exit 0

# --- pull the most recent USER message text from the JSONL transcript ---
# Each line is a transcript event; we want the last one whose role/type is the human.
# Kept dependency-light: python does the JSONL walk if available, else we bail silent.
LAST_USER=""
if command -v python >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; then
  PY=$(command -v python || command -v python3)
  LAST_USER=$("$PY" - "$TRANSCRIPT" <<'PYEOF' 2>/dev/null
import sys, json
path = sys.argv[1]
last = ""
try:
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except Exception:
                continue
            # transcript shapes vary; accept either {"role":"user","content":...}
            # or {"type":"user","message":{"content":...}}
            role = ev.get("role") or ev.get("type")
            if role != "user":
                continue
            msg = ev.get("message", ev)
            content = msg.get("content", "")
            if isinstance(content, list):
                content = " ".join(
                    c.get("text", "") for c in content
                    if isinstance(c, dict) and c.get("type") == "text"
                )
            if isinstance(content, str) and content.strip():
                last = content
    # ignore tool-result / system-reminder-only turns: those start with a tag
    print(last)
except Exception:
    print("")
PYEOF
)
fi

[ -z "$LAST_USER" ] && exit 0

# --- learnable-moment patterns (case-insensitive) ---
# Tuned for PRECISION. Each phrase is something a human says when they are teaching the
# crew a durable lesson, not just steering one task. Generic task language ("fix this",
# "add a test") is deliberately absent — it is NOT a memory.
LEARN_PATTERNS='remember (this|that)|from now on|going forward|always (do|use|run|call|prefer)|never (do|use|run|call|commit|push)|don.?t (do that|do this) again|stop doing|we (decided|chose|agreed)|the (decision|convention) is|my preference|i prefer|i (always|usually) want|note for next time|for the record|as a rule|house style'

if printf '%s' "$LAST_USER" | grep -qiE "$LEARN_PATTERNS"; then
  # stdout on a Stop pass surfaces to the agent as additional context, not a block.
  echo "[learning-loop] That last instruction looks durable (a correction, decision, or standing preference). Consider running /remember to persist it — route it to CLAUDE.md (rule), CONTEXT.md (orientation), an ADR (decision), or .claude/memory/ (preference), proposing the exact text before writing. If it was a one-off, ignore this."
fi

exit 0
