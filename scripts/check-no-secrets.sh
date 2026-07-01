#!/usr/bin/env bash
# check-no-secrets.sh — fail if a tracked file leaks a secret or the maintainer's
# local machine identity into this public repo.
#
# This automates the manual grep the audits already run at every release (author
# handle + host-path sweep). It scans ONLY git-tracked files, so gitignored
# runtime state (memory/, .env, keys) is out of scope by construction.
#
# It flags:
#   - private-key PEM headers (RSA/EC/OPENSSH/DSA/PGP)
#   - absolute home paths (/Users/<user>/ or /home/<user>/) whose user segment
#     is not a recognised placeholder — the real leak is the maintainer's own path
#   - API-key/token shapes: Anthropic (sk-ant-), GitHub PAT (ghp_/github_pat_),
#     AWS access-key id (AKIA...)
#
# Allow-listing is per-OCCURRENCE, not per-line: a line is reported unless EVERY
# pattern hit on it is a recognised placeholder. So a real leak sitting next to a
# placeholder on the same line (as the audit docs do in prose) is still caught.
# Each hit is matched at its own granularity — a home-path hit is `/Users/<user>/`
# — so write .secretsignore rules to that shape (e.g. `/(Users|home)/agricidaniel/`),
# one extended-regex per line. Add benign forms there, don't weaken a pattern.
#
# Exit codes: 0 clean · 1 a real match survived the allow-list
#
# Portable (BSD + GNU); uses `git grep`, no third-party tools. No network.
# CHECK_SECRETS_ROOT overrides the scan root (used by the hermetic test).

set -euo pipefail

ROOT="${CHECK_SECRETS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

# label|extended-regex — kept parallel so hits report which rule fired.
PATTERNS=(
  "private-key|-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----"
  "home-path-macos|/Users/[A-Za-z0-9._-]+/"
  "home-path-linux|/home/[A-Za-z0-9._-]+/"
  "anthropic-key|sk-ant-[A-Za-z0-9_-]{20,}"
  "github-pat|ghp_[A-Za-z0-9]{36}"
  "github-pat-fine|github_pat_[A-Za-z0-9_]{50,}"
  "aws-access-key|AKIA[0-9A-Z]{16}"
)

# A single pattern occurrence is ignored if it matches one of these. First the
# built-in placeholder user-segments (only forms that actually appear as
# placeholders in docs), then any user-supplied rules from .secretsignore.
ALLOW=(
  "/(Users|home)/(you|your[-_]?username|username|user|USER|USERNAME|me|example|placeholder|<[^/>]+>|\{\{[^}]+\}\}|\\\$[A-Za-z_])/"
)
if [ -f .secretsignore ]; then
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac
    ALLOW+=("$line")
  done < .secretsignore
fi

allow_re="$(IFS='|'; printf '%s' "${ALLOW[*]}")"

# Never scan the scanner (it literally contains these patterns), the ignore file,
# or vendored third-party plugin bundles (minified community-plugin main.js files
# carry their *authors'* build paths — not our source, analogous to node_modules).
EXCLUDES=(
  ":(exclude)scripts/check-no-secrets.sh"
  ":(exclude)tests/test_check_no_secrets.sh"
  ":(exclude).secretsignore"
  ":(exclude).obsidian/plugins/*/main.js"
)

hits=0
for entry in "${PATTERNS[@]}"; do
  label="${entry%%|*}"
  regex="${entry#*|}"
  # git grep exits 1 when nothing matches — expected, so guard it.
  while IFS= read -r match; do
    [ -z "$match" ] && continue
    # Examine each occurrence of the pattern on this line independently. The line
    # leaks unless every occurrence is allow-listed. Fail closed: if git grep
    # matched but no occurrence can be re-extracted, treat it as a leak.
    occ_count=0
    leaked=0
    while IFS= read -r occ; do
      [ -z "$occ" ] && continue
      occ_count=$((occ_count + 1))
      printf '%s' "$occ" | grep -Eq "$allow_re" || { leaked=1; break; }
    done < <(printf '%s\n' "$match" | grep -oE "$regex")
    [ "$occ_count" -eq 0 ] && leaked=1
    [ "$leaked" -eq 0 ] && continue
    printf 'LEAK [%s] %s\n' "$label" "$match"
    hits=$((hits + 1))
  done < <(git grep -nEI -e "$regex" -- "${EXCLUDES[@]}" 2>/dev/null || true)
done

if [ "$hits" -gt 0 ]; then
  printf '\ncheck-no-secrets: FAIL — %d suspect line(s) in tracked files.\n' "$hits" >&2
  printf 'If a hit is a legitimate placeholder, add an extended-regex to .secretsignore.\n' >&2
  exit 1
fi

echo "check-no-secrets: OK — no secrets or host identity in tracked files."
