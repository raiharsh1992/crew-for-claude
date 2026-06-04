# secret-patterns.sh — SINGLE SOURCE OF TRUTH for credential-shape detection.
# Sourced by block-dangerous-git.sh AND block-secrets-in-writes.sh. Do NOT fork
# the patterns into either script — edit here and both surfaces pick it up.
#
# This file is SOURCED, never executed directly — no shebang-exec, no top-level
# exit. It defines the credential-shape patterns, the test-secret allowlist, the
# shared block-message text, and the scan_for_secrets() function. Because both
# the Bash-command scan and the file-write scan read the SAME array and SAME
# function, the two surfaces can never drift — that zero-drift guarantee is
# structural, not a matter of discipline.
#
# CASE-SENSITIVE, high-confidence credential SHAPES only — real provider keys and
# password-bearing connection strings. We do NOT match env-var NAMES (JWT_SECRET=
# alone is fine; a real value after it is not) and we EXEMPT the known test
# secrets that CI / test fixtures legitimately use. Over-block is acceptable.
SECRET_PATTERNS=(
  "AKIA[0-9A-Z]{16}"                                  # AWS access key id
  "gh[pousr]_[0-9A-Za-z]{30,}"                         # GitHub PAT / token
  "sk-(ant-)?[0-9A-Za-z_-]{20,}"                       # OpenAI / Anthropic key
  "xox[baprs]-[0-9A-Za-z-]{10,}"                       # Slack token
  "-----BEGIN[ A-Z]*PRIVATE KEY-----"                  # private key block
  "(postgres|postgresql|mysql|mongodb|redis)://[^[:space:]:@/]+:[^[:space:]@/]+@" # conn string with inline password
  "(SECRET|PASSWORD|TOKEN|API_?KEY)[\"' ]*[:=][\"' ]*[A-Za-z0-9+/]{24,}={0,2}"    # KEY = long value
)
# Test/CI values that are SUPPOSED to appear — never block these. Add your own
# project's test-only fixture values here, pipe-separated.
#
# EXACT-MATCH (whole matched span). scan_for_secrets filters with `grep -vxE`, so
# each entry must equal a WHOLE matched secret span, not a substring of one — an
# entry can no longer act as a wildcard that lets a real secret embedding it slip
# through. Practically: list the full span a pattern would extract. For the
# connection-string pattern that span ends at the `@` (e.g. the local-postgres
# fixture span shown below). The base64 entries decode to "test-jwt-secret" /
# "test-hmac-secret" / "test-encryption-key" (common CI fixtures); replace as needed.
TEST_SECRET_ALLOWLIST="dGVzdC1qd3Qtc2VjcmV0|dGVzdC1obWFjLXNlY3JldA|dGVzdC1lbmNyeXB0aW9uLWtleQ|postgres://postgres:postgres@|mysql://root:root@|password123|changeme|example-secret"

# Shared guidance text emitted on a block. Both scanners use this so the two
# surfaces give identical advice.
SECRET_BLOCK_MSG="BLOCKED: payload appears to contain a real secret (matched a high-confidence credential shape). Committing/writing secrets is an auto-fail condition (see your project's CLAUDE.md rules — 'NO SECRETS IN CODE OR GIT, EVER'). If this is a false positive (a test-only value), add it to TEST_SECRET_ALLOWLIST in .claude/hooks/secret-patterns.sh. If it is real, STOP — secrets go through your secret manager and (for sanctioned local use) only into a gitignored .env / .pem / .key / credentials.json / .secret file, never into a tracked source/config file or a shell command."

# scan_for_secrets <text>  → echoes first real-secret hit pattern (empty = clean).
# Returns 0 with the matched pattern on stdout if a secret shape is found, 1 if
# clean. CASE-SENSITIVE (grep -oE, not -i) by design — high-confidence shapes are
# case-specific. Pipes via printf '%s' to preserve newlines in multi-line payloads.
# NOTE the `--` end-of-options marker on BOTH greps: the private-key pattern (and
# any future pattern) begins with '-----', which grep would otherwise parse as
# command-line flags ("grep: unknown option") and silently fail OPEN — a hole.
# `--` forces every following arg to be treated as the pattern, not an option.
#
# ALLOWLIST IS EXACT-MATCH, NOT SUBSTRING. The allowlist filter uses `grep -x`
# (whole-line / full-span match) so an entry only exempts a matched secret span
# that EQUALS it. An earlier version used an unanchored `grep -vE`, which let a
# REAL secret whose value merely CONTAINED an allowlisted token (e.g.
# `postgres://u:realpassword123x@h/db` contains `password123`) slip through as
# clean — the allowlist acted as a wildcard. -x closes that: only an exact test
# fixture value is exempt; a real secret that happens to embed one is still blocked.
scan_for_secrets() {
  local text="$1" pattern hit
  for pattern in "${SECRET_PATTERNS[@]}"; do
    hit=$(printf '%s' "$text" | grep -oE -- "$pattern" | grep -vxE -- "$TEST_SECRET_ALLOWLIST")
    if [ -n "$hit" ]; then
      printf '%s' "$pattern"
      return 0
    fi
  done
  return 1
}
