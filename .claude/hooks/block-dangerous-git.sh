#!/bin/bash
# Block irreversible / forbidden commands before Claude Code executes them.
# Installed as a PreToolUse hook matching the Bash tool (.claude/settings.json).
# Source: adapted from mattpocock/skills git-guardrails-claude-code skill.
#
# This is the HARD BACKSTOP behind the dev-phase blanket Bash(*)/Write(*) allow
# (see CLAUDE.md "Permission posture"). Blanket allow buys velocity; this hook
# makes the handful of TRULY irreversible operations impossible-without-asking
# regardless of the allowlist. A wrong DROP or force-push is not a "rollback the
# deploy" mistake — it's gone.
#
# DESIGN:
#   Agents push feature branches constantly (junior-workers push sub-task
#   branches, dev-leads push feat/* and delete them after merge, the
#   orchestrator pushes pointer-bump branches). So normal `git push` is NOT
#   blocked. Only force-push to the protected branch and genuinely irreversible
#   ops are. Set PROTECTED_BRANCH below to your main branch name.
#
# Exit code 2 = block. Exit code 0 = allow. Fails SAFE (over-blocks), never open.

# Single source of truth for credential-shape detection + scan_for_secrets. The
# SAME file is sourced by block-secrets-in-writes.sh, so the Bash-command surface
# and the file-write surface can never drift on what counts as a secret.
source "$(dirname "$0")/secret-patterns.sh"

# Protected branch resolution (first non-empty wins):
#   1. PROTECTED_BRANCH env override (set by /install or settings env) — explicit, always wins.
#   2. The repo's actual default branch from origin/HEAD (so master vs main is auto-correct).
#   3. Literal "main" as a last resort if detection fails.
# This avoids the silent-inert failure mode where a hardcoded "main" default leaves a
# "master" repo unprotected against force-push (the backstop pointed at a branch that
# doesn't exist).
if [ -z "$PROTECTED_BRANCH" ]; then
  PROTECTED_BRANCH=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')
fi
if [ -z "$PROTECTED_BRANCH" ]; then
  # No origin/HEAD (e.g. no remote yet): fall back to the current branch if it looks
  # like a main branch, else "main".
  CUR=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
  case "$CUR" in
    main|master|trunk|develop) PROTECTED_BRANCH="$CUR" ;;
    *) PROTECTED_BRANCH="main" ;;
  esac
fi

INPUT=$(cat)

# Extract .tool_input.command. jq is NOT guaranteed in Git Bash on Windows; if
# we depended on it silently the hook would fail OPEN on every command (which is
# how this backstop was inert before this rewrite). Fall back through python,
# then scan the raw event — failing SAFE (possible false-positive block), never
# failing open.
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

# Patterns are extended regex (grep -E), case-insensitive match applied below.
# Each line is something that is irreversible or explicitly forbidden. Normal
# feature-branch pushes/commits are intentionally NOT here.
# Patterns target COMMAND structure. Gaps use a bounded "not a shell separator"
# class so a pattern can't span an entire issue-body/sentence — an early bug
# blocked a `gh issue create` whose body merely MENTIONED these phrases. SQL
# destruction is gated on an EXECUTION context (psql / -c / mysql / .sql /
# execute) so prose like "DROP TABLE" in a commit message or issue body does NOT
# trip it; only an actual run does. Matching is case-insensitive (grep -i).
# Over-blocking is acceptable (human confirms); failing open is not.
SEP='[^|;&]'   # stays within a single shell command segment
DANGEROUS_PATTERNS=(
  # --- force-push to the protected branch ---
  "git${SEP}{0,20}push${SEP}{0,60}(--force|-f|--force-with-lease|--mirror)${SEP}{0,40}${PROTECTED_BRANCH}"
  "git${SEP}{0,20}push${SEP}{0,60}${PROTECTED_BRANCH}${SEP}{0,40}(--force|-f|--force-with-lease)"
  "git${SEP}{0,20}push${SEP}{0,40}--mirror"
  # --- destructive git on the working tree ---
  "git${SEP}{0,20}reset[[:space:]]+--hard"
  "git${SEP}{0,20}clean[[:space:]]+-[a-z]*f"
  "git${SEP}{0,20}checkout[[:space:]]+\.([[:space:]]|\$)"
  "git${SEP}{0,20}restore[[:space:]]+\.([[:space:]]|\$)"
  # NOTE: `git branch -D` (force-delete, can drop UNMERGED work) is blocked below
  # via a CASE-SENSITIVE check — it must NOT live in this case-insensitive loop,
  # because `-i` would also catch the safe `git branch -d` (merged-only delete,
  # which git refuses on unmerged branches and so can never lose work).
  # --- destructive filesystem: any recursive+force rm ---
  "(^|[[:space:]])rm[[:space:]]+-[a-z]*r[a-z]*f"
  "(^|[[:space:]])rm[[:space:]]+-[a-z]*f[a-z]*r"
  "(^|[[:space:]])rm[[:space:]]+-r[[:space:]]+-f"
  "(^|[[:space:]])rm[[:space:]]+-f[[:space:]]+-r"
  # --- irreversible DB destruction, only in an EXECUTION context ---
  # (Stack-AGNOSTIC DB tooling only. Framework/ORM-specific destructive commands —
  # e.g. `alembic downgrade base` — are enforced by the relevant language PACK,
  # not here, to keep this core hook language-neutral.)
  "(psql|mysql|-c|--command|execute|\.sql)${SEP}{0,80}(drop[[:space:]]+(table|database|schema|owned)|truncate[[:space:]]+(table[[:space:]]+)?[a-z_\"])"
  "(^|[[:space:]])dropdb([[:space:]]|\$)"
)

for pattern in "${DANGEROUS_PATTERNS[@]}"; do
  if printf '%s' "$COMMAND" | grep -qiE "$pattern"; then
    echo "BLOCKED: command matches irreversible/forbidden pattern '$pattern'. This is the hard backstop behind the dev-phase blanket allow (see CLAUDE.md 'Permission posture'). The user has NOT authorized this operation — it is destructive to git history (force-push to the protected branch), the working tree (reset --hard / clean -f), the filesystem (rm -rf), or the database (DROP/TRUNCATE). STOP and ask the user. Do not work around the block. Normal feature-branch pushes are allowed — only these specific operations require a human." >&2
    exit 2
  fi
done

# --- CASE-SENSITIVE: git branch -D (force-delete) ONLY ---
# Blocks the destructive force-delete (drops unmerged work) while ALLOWING the
# safe `git branch -d` (merged-only; git refuses it on unmerged branches).
# Uses a case-sensitive grep so `-d` is not swept up with `-D`.
if printf '%s' "$COMMAND" | grep -qE "git${SEP}{0,20}branch[[:space:]]+(-[a-zA-Z]*D|--delete[[:space:]]+--force|--force[[:space:]]+--delete)"; then
  echo "BLOCKED: 'git branch -D' force-deletes a branch even if it has UNMERGED commits — that can lose work. Use 'git branch -d' (safe; deletes only branches already merged) instead, or ask the user if you truly need the force-delete." >&2
  exit 2
fi

# --- Secrets scan (defense-in-depth for the "no secrets in code" auto-fail) ---
# Patterns + allowlist + scan come from the sourced secret-patterns.sh — the same
# single source the file-write hook uses. Blocks the command outright if a real
# secret shape is present; if a real secret needs to move, the human does it.
if scan_for_secrets "$COMMAND" >/dev/null; then
  echo "$SECRET_BLOCK_MSG" >&2
  exit 2
fi

# --- Collision warning: HEAD-moving git op WHILE the tree shows submodule churn -
# Failure mode this catches (a parallel-session collision): two agents/sessions
# work the same tree at once. One moves HEAD (checkout -b, commit --amend,
# rebase, reset, cherry-pick) while the OTHER has left submodules dirty. The
# HEAD-mover then tangles history it didn't create. The unmistakable tell:
# `git status` shows MODIFIED SUBMODULES the acting session never touched — the
# fingerprint of another session live in the tree.
#
# This guard fires ONLY on genuinely HEAD-moving / history-tangling git ops —
# NOT on the smooth daily flow (plain commit / add / push / checkout <branch>).
# When such an op coincides with submodule churn in the tree, it WARNS so the
# agent stops and confirms no parallel session is active before moving HEAD.
#
# WARN, never block: a dirty tree is often legitimately the acting session's own
# work, so a hard block would false-positive and break the flow. The warning at
# the decision moment is the whole fix. Exit 0 (stderr on a PreToolUse pass
# surfaces to the agent as context, not as a failure).
HEADMOVE_RE="git${SEP}{0,20}(checkout[[:space:]]+-b|switch[[:space:]]+-c|branch[[:space:]]+(-f|-M|--force)|commit${SEP}{0,40}--amend|rebase|reset|cherry-pick)"
if printf '%s' "$COMMAND" | grep -qiE "$HEADMOVE_RE"; then
  # Cheap, read-only check for submodule churn. `git status --porcelain` marks a
  # changed submodule with a line whose path is a known submodule; the simplest
  # robust signal is a porcelain entry tagged as a submodule modification.
  SM_DIRTY=$(git status --porcelain 2>/dev/null | grep -E '^[ MARC]M ' 2>/dev/null | head -1)
  # Also catch the explicit "modified content / new commits" submodule shape.
  SM_DIRTY2=$(git submodule status 2>/dev/null | grep -E '^\+' 2>/dev/null | head -1)
  if [ -n "$SM_DIRTY" ] || [ -n "$SM_DIRTY2" ]; then
    echo "[collision-warning] You are about to run a HEAD-MOVING git op AND the working tree shows submodule churn you may not have created. This is the fingerprint of a parallel-session collision (another session moving HEAD underneath you). BEFORE proceeding: (1) confirm no other Claude/engineering session is live in this tree; (2) confirm those modified submodules are YOURS; (3) if unsure, STOP and ask the user. Recovery if it tangles: your commit survives in 'git reflog'. This is a warning, not a block." >&2
  fi
fi

exit 0
