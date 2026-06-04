#!/bin/bash
# Block spawning the ORCHESTRATOR as a sub-agent. Installed as a PreToolUse hook matching
# the Task tool (.claude/settings.json).
#
# THE RULE (see .claude/memory/agent-lane-discipline.md): the orchestrator role `lead-agent`
# is played by the MAIN SESSION and must NEVER be spawned as a sub-agent. A spawned
# orchestrator self-blocks on nested Task/Bash and burns tokens for nothing — a real,
# expensive failure we hit before. This hook makes that mistake impossible, turning the
# "lead-agent is NOT spawned as a sub-agent" prose in lead-agent.md into a machine gate.
#
# It blocks ONLY a Task whose subagent_type is the orchestrator (lead-agent / pa-agent,
# a legacy alias, covered for safety). Every other agent spawn is allowed untouched.
#
# Fail-safe: jq -> python -> raw fallback, same as the other hooks. If the field can't be
# extracted we DO NOT block (a Task we can't parse is almost never the orchestrator, and
# over-blocking every Task would wedge the whole crew). Exit 2 = block, 0 = allow.

INPUT=$(cat)

# Extract .tool_input.subagent_type (jq -> python -> python3 -> empty).
if command -v jq >/dev/null 2>&1; then
  SUBAGENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)
elif command -v python >/dev/null 2>&1; then
  SUBAGENT=$(printf '%s' "$INPUT" | python -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("subagent_type",""))' 2>/dev/null)
elif command -v python3 >/dev/null 2>&1; then
  SUBAGENT=$(printf '%s' "$INPUT" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("subagent_type",""))' 2>/dev/null)
else
  SUBAGENT=""
fi

# Normalize to lowercase for a robust compare.
SUBAGENT_LC=$(printf '%s' "$SUBAGENT" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')

case "$SUBAGENT_LC" in
  lead-agent|leadagent|pa-agent|paagent)
    echo "BLOCKED: refusing to spawn the orchestrator ('$SUBAGENT') as a sub-agent. The orchestrator role (lead-agent) is played by the MAIN SESSION and must NEVER be spawned — a spawned orchestrator self-blocks on nested Task/Bash and wastes tokens (a real failure we hit before). Do the orchestration from the main session directly: decompose the work and spawn the right DOMAIN LEAD (dev-lead, design-lead, devops-lead, research-lead, test-lead, security-lead, media-lead) or architect for each piece. See .claude/agents/lead-agent.md for the routing rules." >&2
    exit 2
    ;;
esac

exit 0
