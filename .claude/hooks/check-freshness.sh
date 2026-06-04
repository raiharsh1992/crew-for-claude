#!/bin/bash
# Freshness-loop SENSOR (Loop 3 of the three loops; see docs/adr/0002). Installed as a
# SessionStart hook (.claude/settings.json). Fires when a session begins, AFTER onboarding
# is done (it stays silent on un-installed / un-oriented repos — that's Loop 1's job). Its
# job: cheaply detect that CONTEXT.md has likely gone STALE relative to the code, and nudge
# toward `drift-audit` (the actuator). It NEVER writes and NEVER blocks.
#
# THE CHEAP SIGNAL (the design problem from ADR-0002): a true doc-vs-code diff is expensive
# and model-driven — that's `drift-audit`'s job, on demand. The SENSOR just needs a cheap,
# deterministic "probably stale" tripwire that does NOT fire every session. We use git:
#   - Find the last commit that touched CONTEXT.md.
#   - Count code commits SINCE then that touched source files but NOT CONTEXT.md.
#   - If that count crosses a threshold, the doc is probably behind the code → nudge.
# This is a HEURISTIC (it can't know if those commits actually changed surfaces) — so it
# only ever SUGGESTS running the real audit; it never claims drift as fact.
#
# DESIGN CONSTRAINTS (shared with the other sensors):
#   - Fail SILENT on any error (no git, shallow clone, detached state). A missed nudge is
#     fine; drift-audit is always available on demand.
#   - Stay silent unless the crew is installed AND CONTEXT.md is authored — a fresh repo's
#     onboarding nudge (Loop 1) must not collide with a freshness nudge.
#   - Tunable threshold via STALE_THRESHOLD env (default 15). Conservative on purpose:
#     better to under-nudge than to cry wolf and get tuned out.
#
# Exit 0 always. Output (if any) is an advisory nudge, not a control signal.

cat >/dev/null 2>&1   # drain stdin (SessionStart payload); we work from the filesystem/git

ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
[ -z "$ROOT" ] && exit 0   # not a git repo → no cheap signal available, stay silent

# --- Gate: only run on an installed + oriented repo (don't collide with onboarding) ---
[ -f "$ROOT/.claude/skills-config.json" ] || exit 0
[ -f "$ROOT/CONTEXT.md" ] || exit 0
grep -q "PROJECT / MODULE NAME\|PROJECT NAME" "$ROOT/CONTEXT.md" 2>/dev/null && exit 0  # still template

STALE_THRESHOLD="${STALE_THRESHOLD:-15}"

# --- Last commit that touched CONTEXT.md ---
git -C "$ROOT" ls-files --error-unmatch CONTEXT.md >/dev/null 2>&1 || exit 0  # not tracked yet → nothing to compare against
LAST_CONTEXT_COMMIT=$(git -C "$ROOT" log -1 --format=%H -- CONTEXT.md 2>/dev/null)
[ -z "$LAST_CONTEXT_COMMIT" ] && exit 0

# --- Count code-bearing commits since then that did NOT also touch CONTEXT.md ---
# We look at commits AFTER the last CONTEXT.md commit, restricted to source-ish paths,
# and EXCLUDE any that also touched CONTEXT.md (those kept the doc fresh in the same change,
# exactly as the contract requires — they don't count as drift).
SINCE_RANGE="${LAST_CONTEXT_COMMIT}..HEAD"

# commits in range that touched code paths (broad source globs; tune per project as needed)
CODE_COMMITS=$(git -C "$ROOT" log --format=%H "$SINCE_RANGE" -- \
  '*.py' '*.js' '*.ts' '*.tsx' '*.jsx' '*.java' '*.go' '*.rs' '*.rb' '*.kt' \
  'src/*' 'app/*' 'lib/*' 'migrations/*' 'alembic/*' 2>/dev/null)

# commits in the same range that ALSO touched CONTEXT.md (fresh-in-same-change → exclude)
DOC_FRESH_COMMITS=$(git -C "$ROOT" log --format=%H "$SINCE_RANGE" -- CONTEXT.md 2>/dev/null)

# count code commits not present in the doc-fresh set
DRIFT_COUNT=0
if [ -n "$CODE_COMMITS" ]; then
  while IFS= read -r c; do
    [ -z "$c" ] && continue
    if ! printf '%s\n' "$DOC_FRESH_COMMITS" | grep -qF "$c" 2>/dev/null; then
      DRIFT_COUNT=$((DRIFT_COUNT+1))
    fi
  done <<EOF
$CODE_COMMITS
EOF
fi

if [ "$DRIFT_COUNT" -ge "$STALE_THRESHOLD" ]; then
  echo "[freshness] CONTEXT.md may be STALE: ~${DRIFT_COUNT} code commits have landed since it was last updated (threshold ${STALE_THRESHOLD}). The orientation contract says docs update in the SAME change as the code — this gap suggests they didn't. Consider running drift-audit (the honest mirror) to check doc-vs-code drift, then patch CONTEXT.md for anything that moved. (Heuristic by commit count — it can't confirm a surface actually changed; the audit does. Tune via STALE_THRESHOLD.)"
fi

exit 0
