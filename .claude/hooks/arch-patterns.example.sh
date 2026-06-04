# arch-patterns.example.sh — SINGLE SOURCE OF TRUTH for architecture-violation patterns.
# Sourced by block-architecture-violations.sh. Do NOT fork the patterns into the hook —
# edit here and the hook reads the same array.
#
# This file is SOURCED, never executed directly — no shebang-exec, no top-level exit.
# It defines the architecture-pattern list that the PreToolUse hook scans against.
# Because the hook sources this ONCE, the pattern list has a single-source guarantee —
# that zero-drift guarantee is structural, not a matter of discipline.
#
# INCLUSION BAR: patterns MUST be lexically unambiguous. A pattern that matches
# legitimate code (a variable name, a library import) is a false-positive risk and
# is REJECTED. Patterns MUST be high-confidence architecture violations with near-zero
# false-positive risk. Examples of GOOD patterns: a call to a deprecated destructive
# operation, a SQL DROP/TRUNCATE that should never appear in version control, a
# hardcoded timestamp check that indicates a forbidden design. Examples of BAD patterns:
# a substring match ("delete") that would catch legitimate variable names
# ("deletedAt", "can_delete"), or a method name that exists in multiple contexts.
#
# HOW TO EXTEND: This file ships with EXAMPLE patterns. Your project should create a
# .claude/hooks/arch-patterns-local.sh file (gitignored or committed, your choice) with
# YOUR OWN rules. The block-architecture-violations.sh hook checks for the local file
# FIRST and sources it if it exists; if not, it falls back to this example file. This
# way your project rules never need to fork this generic template — they live in a
# dedicated local file and can be maintained independently. See the hook's ARCH_PATTERNS_FILE
# env var for how to override the default search path.

# ARCH_PATTERNS — array of regex patterns that indicate architecture violations.
# High-confidence shapes only. Each pattern is grep -E compatible (ERE).
# CASE-SENSITIVE by design (arch violations are usually case-specific).
ARCH_PATTERNS=(
  # FORBIDDEN DESTRUCTIVE OPERATIONS
  # ────────────────────────────────
  # DROP TABLE / TRUNCATE — versioned code should never contain actual destructive
  # SQL. Migrations use 'CREATE TABLE IF NOT EXISTS' + 'ALTER TABLE'; downgrades
  # must be idempotent. A bare DROP or TRUNCATE in a migrated schema is a red flag.
  "DROP TABLE[[:space:]]"
  "TRUNCATE TABLE[[:space:]]"

  # HARD DELETE with no soft-delete fallback — a forbidden pattern in business logic.
  # Detects a direct cascading delete on any table (matches 'DELETE FROM <table>'
  # followed by optional whitespace/newlines and WHERE/semicolon, catching the shape
  # but not legitimate SELECT/UPDATE statements or the word 'delete' in comments).
  "DELETE FROM[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*(WHERE|;|$)"

  # FORBIDDEN TIME-BASED LOGIC
  # ──────────────────────────
  # Hardcoded datetime comparisons that indicate a forbidden "temporal coupling"
  # pattern (code that behaves differently on a specific date/time). Detects the
  # pattern "new Date()" / "now()" / "time.Now()" directly compared or used in
  # conditionals without a dependency-injected clock abstraction.
  "if[[:space:]]*\\([^)]*\\b(new Date\\(\\)|time\\.Now\\(\\)|DateTime\\.UtcNow)\\b"

  # GLOBAL STATE / SINGLETON MUTATIONS
  # ──────────────────────────────────
  # Direct mutation of a global dictionary/object that should be immutable.
  # Catches 'GLOBAL_CONFIG[...]=' or 'sys.modules[...]=' outside of setup code.
  # This pattern is strict: it requires the assignment operator and the global name.
  "\\bGLOBAL_CONFIG\\[[^]]*\\][[:space:]]*=[^=]"
)
