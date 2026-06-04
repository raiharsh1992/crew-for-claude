#!/bin/bash
# Block vendor/model attribution terms in git/gh commands (Crew for Claude).
#
# TOGGLE: This hook is DEFAULT OFF when no attribution trailer is configured.
# To enable, set ATTRIBUTION_TRAILER in your environment OR set the
# 'attributionTrailer' field in .claude/skills-config.json to a non-empty value.
# When no value is configured the hook exits 0 (safe no-op) — a fresh consumer
# is not surprised by blocked commits.
#
# THE RULE (when enabled): git commit messages, PR titles/bodies, issue bodies,
# and PR reviews must never name the underlying model vendor or tiers. On the
# git/GitHub surface, work is attributed to "Crew for Claude" — not to
# Claude / Anthropic / Sonnet / Haiku / Opus / "Generated with Claude".
# The exact trailer is configurable via .claude/skills-config.json key
# 'attributionTrailer' — only that exact value is allowed.
#
# Installed as a PreToolUse hook matching Bash commands (.claude/settings.json).
# Scans: git commit, gh pr create, gh pr review, gh issue create/comment (only).
#
# Exit code 2 = block (banned term found). Exit code 0 = allow. Fails SAFE: if
# the Bash command cannot be parsed, allow it (style guardrail, not safety gate).

INPUT=$(cat)

# Extract .tool_input.command. jq is NOT guaranteed in Git Bash on Windows; fall back
# through python, then raw event — failing SAFE (allow if unparseable).
if command -v jq >/dev/null 2>&1; then
  COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command' 2>/dev/null)
elif command -v python >/dev/null 2>&1; then
  COMMAND=$(printf '%s' "$INPUT" | python -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null)
elif command -v python3 >/dev/null 2>&1; then
  COMMAND=$(printf '%s' "$INPUT" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null)
else
  COMMAND=""
fi

if [ -z "$COMMAND" ] || [ "$COMMAND" = "null" ]; then
  COMMAND="$INPUT"
fi

# Only check commands that are relevant to attribution (git/gh commands).
# Fail SAFE: if it's not a git/gh command, allow it.
if ! printf '%s' "$COMMAND" | grep -qiE '^\s*(git|gh)\s+'; then
  exit 0
fi

# --- ATTRIBUTION TOGGLE ---
# Read from env var first, then from skills-config.json, else empty (= disabled).
ATTRIBUTION_TRAILER="${ATTRIBUTION_TRAILER:-}"
if [ -z "$ATTRIBUTION_TRAILER" ] && [ -f ".claude/skills-config.json" ]; then
  if command -v jq >/dev/null 2>&1; then
    ATTRIBUTION_TRAILER=$(jq -r '.attributionTrailer // empty' ".claude/skills-config.json" 2>/dev/null)
  elif command -v python3 >/dev/null 2>&1; then
    ATTRIBUTION_TRAILER=$(python3 -c "import json; c=json.load(open('.claude/skills-config.json')); print(c.get('attributionTrailer',''))" 2>/dev/null)
  elif command -v python >/dev/null 2>&1; then
    ATTRIBUTION_TRAILER=$(python -c "import json; c=json.load(open('.claude/skills-config.json')); print(c.get('attributionTrailer',''))" 2>/dev/null)
  fi
fi

# If no attribution value is configured, this hook is a safe no-op.
if [ -z "$ATTRIBUTION_TRAILER" ]; then
  exit 0
fi

# HARDCODED banned terms — vendor names, model tiers, "Generated with" phrase.
# These are universal and always blocked (never configurable).
# Pattern explanation (matching check-commit-msg.sh):
#   - \banthropic\b, \bsonnet\b, \bhaiku\b, \bopus\b: vendor/model names (word boundaries)
#   - \bclaude[[:space:]]+(code|3|3\.5|opus|sonnet|haiku): Claude followed by version/model name
#   - generated[[:space:]]+with[[:space:]]+claude: attribution phrase
# These patterns allow "Crew for Claude" but block bare "Claude" in vendor contexts.
FORBIDDEN_PATTERN='\banthropic\b|\bsonnet\b|\bhaiku\b|\bopus\b|\bclaude[[:space:]]+(code|3|3\.5|opus|sonnet|haiku)\b|generated[[:space:]]+with[[:space:]]+claude'

# Check for banned terms (case-insensitive).
if printf '%s' "$COMMAND" | grep -qiE "$FORBIDDEN_PATTERN"; then
  echo "BLOCKED: command contains banned attribution term. On git/GitHub, work is attributed to 'Crew for Claude', not to Claude / Anthropic / model tiers. Remove the vendor/model name from the message/body/trailer and try again." >&2
  exit 2
fi

# Now check for the trailer: the command must NOT contain any Co-Authored-By trailer
# (the check-commit-msg hook handles git-native trailers; this hook catches gh-pr-* / gh-issue-*).
# If present, it MUST be the exact trailer from skills-config.json.

TRAILER="$ATTRIBUTION_TRAILER"

# Check for ANY Co-Authored-By trailer in the command (common in gh-pr-create / gh-issue-create).
# If one exists, it MUST match the configured trailer from skills-config.json (if present).
# If trailer is present in the command but not in the config, allow it (fail safe for config parsing).
# If both are present, they must match exactly.
FOUND_TRAILER=$(printf '%s' "$COMMAND" | grep -oiE 'Co-Authored-By:[^"'\'']+ [^"'\'']+ [^"'\'']+ <[^>]+>' | head -1)

if [ -n "$FOUND_TRAILER" ] && [ -n "$TRAILER" ]; then
  # Both config trailer and command trailer exist; they must match exactly.
  if [ "$FOUND_TRAILER" != "$TRAILER" ]; then
    echo "BLOCKED: Co-Authored-By trailer does not match the configured trailer. Expected: '$TRAILER'. Found: '$FOUND_TRAILER'. Use the exact configured trailer or remove it (the hook will allow the commit/PR without one)." >&2
    exit 2
  fi
fi

exit 0
