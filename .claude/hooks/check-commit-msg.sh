#!/bin/bash
# Commit-message NAMING GUARD for Crew for Claude.
#
# TOGGLE: This hook is DEFAULT OFF when no attribution trailer is configured.
# To enable, set ATTRIBUTION_TRAILER in your environment OR set the
# 'attributionTrailer' field in .claude/skills-config.json to a non-empty value.
# When no value is configured the hook exits 0 (safe no-op) — a fresh consumer
# is not surprised by unexplained commit rejections.
#
# THE RULE (when enabled): documentation may name models freely, but the
# GIT/GITHUB ACTIVITY surface (commit messages, and by extension PR titles/bodies
# derived from them) must never name the underlying model vendor or tiers. On git,
# the work is attributed to "Crew for Claude" — not to Claude / Anthropic /
# Sonnet / Haiku / Opus.
#
# This is a git `commit-msg` hook. Install it by pointing .git/hooks/commit-msg
# at this script (the repo ships a thin shim that does exactly that; see
# .claude/hooks/README.md). Git passes the path to the prepared commit message
# file as $1.
#
# Exit 0 = allow the commit. Exit 1 = reject it (git aborts the commit). Fails
# CLOSED: if it can't read the message file, it allows (a guard must never wedge
# committing), but any forbidden token present rejects.

MSG_FILE="$1"
[ -z "$MSG_FILE" ] || [ ! -f "$MSG_FILE" ] && exit 0   # nothing to check -> don't block

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

# Strip comment lines (git's commented template lines start with '#') before scanning,
# so the standard commit template / verbose diff doesn't cause false hits.
BODY=$(grep -v '^#' "$MSG_FILE" 2>/dev/null)
[ -z "$BODY" ] && exit 0

# Forbidden tokens on the git surface. Word-boundary, case-insensitive. "claude" is
# allowed ONLY as part of the product name "Crew for Claude", so we do NOT blanket-ban
# "claude"; we ban the vendor + the model tiers, plus a bare "Co-Authored-By" trailer
# naming any of them.
FORBIDDEN='\banthropic\b|\bsonnet\b|\bhaiku\b|\bopus\b|\bclaude[[:space:]]+(code|3|3\.5|opus|sonnet|haiku)\b|generated[[:space:]]+with[[:space:]]+claude'

HIT=$(printf '%s' "$BODY" | grep -niE "$FORBIDDEN" 2>/dev/null | head -3)

if [ -n "$HIT" ]; then
  echo "─────────────────────────────────────────────────────────────────" >&2
  echo "COMMIT BLOCKED — naming guard (Crew for Claude)" >&2
  echo "" >&2
  echo "The commit message names a model vendor or tier. On the git/GitHub surface," >&2
  echo "work is attributed to 'Crew for Claude' — never to" >&2
  echo "Claude / Anthropic / Sonnet / Haiku / Opus. (Documentation may name models;" >&2
  echo "commit messages may not.)" >&2
  echo "" >&2
  echo "Offending line(s):" >&2
  printf '  %s\n' "$HIT" >&2
  echo "" >&2
  echo "Fix: reword the message. For attribution use the configured trailer from" >&2
  echo "  .claude/skills-config.json ('attributionTrailer') or ATTRIBUTION_TRAILER env var." >&2
  echo "─────────────────────────────────────────────────────────────────" >&2
  exit 1
fi

exit 0
