#!/bin/bash
# Onboarding-loop SENSOR (Loop 1 of the three loops; see docs/adr/0002). Installed as a
# SessionStart hook (.claude/settings.json). Fires when a session begins. Its only job is
# to detect (a) whether the crew is INSTALLED here yet, and (b) what SHAPE the folder is —
# then surface the single right one-line offer that turns "install" into "alive". It NEVER
# writes and NEVER blocks; it only orients. /install and /orient are the actuators.
#
# WHY A HOOK: the wow-moment has to happen WITHOUT the user knowing what to type. A fresh
# user who just dropped the kit into a folder doesn't know /install exists. A deterministic
# SessionStart sensor meets them where they are and offers the next step in their words.
#
# DESIGN CONSTRAINTS (shared with suggest-memory.sh):
#   - SessionStart hooks: stdout is injected as additionalContext for the session. We emit
#     a short, high-signal orientation block ONCE per fresh session — not a wall of text.
#   - Idempotent feel: if the crew is already installed AND context files are filled, we
#     stay SILENT (a configured repo doesn't need an onboarding nudge every session). The
#     freshness loop (Loop 3) owns the ongoing-health nudge, not this one.
#   - Fail SILENT on any error. A missed offer is recoverable (run /install by hand); a
#     spurious wall of text every session trains the user to ignore the sensor.
#   - No jq/python hard dependency for the detection — it's filesystem shape, done in pure
#     bash so it runs anywhere Git Bash does.
#
# Exit 0 always. Output (if any) is advisory orientation, not a control signal.

INPUT=$(cat 2>/dev/null)   # SessionStart payload (source, cwd, …) — we don't strictly need it

# --- where are we? prefer the git toplevel, fall back to PWD ---
ROOT=$(git rev-parse --show-toplevel 2>/dev/null)
[ -z "$ROOT" ] && ROOT="$PWD"

# --- INSTALLED? the crew is "wired" once skills-config.json exists ---
INSTALLED=0
[ -f "$ROOT/.claude/skills-config.json" ] && INSTALLED=1

# --- CONTEXT filled? a present-but-untouched template still counts as NOT filled. ---
# Heuristic: the templates carry the literal placeholder "<PROJECT NAME>" / "<PROJECT /".
# If CONTEXT.md exists and no longer contains that placeholder, treat it as authored.
CONTEXT_FILLED=0
if [ -f "$ROOT/CONTEXT.md" ]; then
  if ! grep -q "PROJECT / MODULE NAME\|PROJECT NAME" "$ROOT/CONTEXT.md" 2>/dev/null; then
    CONTEXT_FILLED=1
  fi
fi

# --- If fully set up, stay silent. The session is a normal working session. ---
if [ "$INSTALLED" = "1" ] && [ "$CONTEXT_FILLED" = "1" ]; then
  exit 0
fi

# --- Detect FOLDER SHAPE (filesystem-only, cheap) ---
# empty       : no code markers, no .git → a brand-new project folder
# single      : one git root, markers at/under it
# multi-repo  : several .git dirs OR a .gitmodules superproject OR sibling repo dirs
# unknown     : has files but no recognizable markers
shape="unknown"

# count git roots one level down + at root
GIT_ROOTS=0
[ -d "$ROOT/.git" ] && GIT_ROOTS=$((GIT_ROOTS+1))
for d in "$ROOT"/*/; do
  [ -d "${d}.git" ] && GIT_ROOTS=$((GIT_ROOTS+1))
done
HAS_SUBMODULES=0
[ -f "$ROOT/.gitmodules" ] && HAS_SUBMODULES=1

# any code markers anywhere shallow? (exclude vendored deps so node_modules/*/package.json
# doesn't masquerade as a project marker)
MARKERS=$(find "$ROOT" -maxdepth 2 ! -path '*/node_modules/*' ! -path '*/.git/*' \( \
  -name pom.xml -o -name build.gradle -o -name build.gradle.kts -o \
  -name package.json -o -name pyproject.toml -o -name setup.cfg -o \
  -name requirements.txt -o -name go.mod -o -name Cargo.toml -o -name '*.tf' \
  \) 2>/dev/null | head -1)

# any files at all (excluding .git / the kit's own .claude)?
HAS_FILES=$(find "$ROOT" -maxdepth 1 -mindepth 1 \
  ! -name .git ! -name .claude ! -name .gitignore 2>/dev/null | head -1)

if [ "$HAS_SUBMODULES" = "1" ] || [ "$GIT_ROOTS" -gt 1 ]; then
  shape="multi-repo"
elif [ -z "$MARKERS" ] && [ -z "$HAS_FILES" ]; then
  shape="empty"
elif [ -n "$MARKERS" ]; then
  shape="single"
else
  shape="unknown"
fi

# --- Compose the one right offer per (installed?, shape) ---
echo "════════════════════════════════════════════════════════════════"
echo "  crew-for-claude — onboarding (this looks like a first run here)"
echo "════════════════════════════════════════════════════════════════"

if [ "$INSTALLED" = "0" ]; then
  case "$shape" in
    empty)
      echo "Shape: EMPTY FOLDER — a brand-new project."
      echo "Offer: describe what you want to build and I'll scaffold it — lay down CLAUDE.md +"
      echo "       CONTEXT.md from the templates, then run /install to wire hooks + the verify map."
      echo "       Start by telling me the goal, or run /install --dry-run to preview the wiring."
      ;;
    single)
      if [ "$GIT_ROOTS" -ge 1 ]; then
        echo "Shape: EXISTING SINGLE REPO."
      else
        echo "Shape: EXISTING PROJECT (code present, no git root yet — 'git init' when ready)."
      fi
      echo "Offer: I can ORIENT this project for you — run /orient to generate a real CONTEXT.md"
      echo "       (glossary + module map + 'read this first') from the actual code, then /install"
      echo "       --dry-run to preview wiring the crew. Orientation first makes everything after sharper."
      ;;
    multi-repo)
      echo "Shape: MULTI-REPO WORKSPACE (multiple git roots / submodules)."
      echo "Offer: run /install --dry-run — it resolves the repo universe into repos.config.js and"
      echo "       plans the per-repo verify map. Then /orient each repo to generate its CONTEXT.md."
      ;;
    *)
      echo "Shape: files present, no familiar language markers yet."
      echo "Offer: tell me what this is, or run /install --dry-run to let the crew inspect and plan."
      ;;
  esac
else
  # installed but context not filled
  echo "Crew is INSTALLED, but CONTEXT.md is still the template (no orientation yet)."
  echo "Offer: run /orient to generate a real CONTEXT.md from the code — the single"
  echo "       highest-leverage thing you can do; every agent reads it first."
fi

echo "────────────────────────────────────────────────────────────────"
echo "(This nudge appears only until the crew is installed and CONTEXT.md is filled.)"
exit 0
