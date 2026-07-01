#!/usr/bin/env bash
# test_check_no_secrets.sh — hermetic tests for scripts/check-no-secrets.sh.
#
# Builds a throwaway git tree per case and points the scanner at it via
# CHECK_SECRETS_ROOT, asserting detection, per-occurrence allow-listing, the
# .secretsignore hook, vendored-bundle exclusion, and exit codes. The star case
# is co-occurrence: a real leak on the same line as a placeholder must still be
# reported (the whole-line-allow false-negative caught in review). No network.
#
# All leak-shaped fixtures are assembled at RUNTIME (never written as literals)
# so this file carries no secret-shaped strings of its own — it stays clean for
# both `make check-secrets` and local pre-write secret guards.
#
# Usage: bash tests/test_check_no_secrets.sh
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCANNER="$REPO/scripts/check-no-secrets.sh"

PASS=0
FAILN=0
ok()  { echo "OK   $1"; PASS=$((PASS + 1)); }
bad() { echo "FAIL $1"; FAILN=$((FAILN + 1)); }

SB=""
new_sandbox() {
  SB="$(mktemp -d)"
  git -C "$SB" init -q
}
cleanup() { [ -n "$SB" ] && rm -rf "$SB"; }
trap cleanup EXIT

put() {  # put <relative-path>  (content on stdin)
  local rel="$1"
  mkdir -p "$SB/$(dirname "$rel")"
  cat > "$SB/$rel"
}

scan() {  # stage the tree and run the scanner; sets $RC and $OUT
  git -C "$SB" add -A .
  OUT="$(CHECK_SECRETS_ROOT="$SB" bash "$SCANNER" 2>&1)"
  RC=$?
}

expect_rc() {  # <label> <expected_rc>
  if [ "$RC" -eq "$2" ]; then ok "$1 (rc=$RC)"; else bad "$1: expected rc=$2, got $RC — $OUT"; fi
}
expect_contains() {  # <label> <needle>
  case "$OUT" in *"$2"*) ok "$1" ;; *) bad "$1: output missing '$2' — $OUT" ;; esac
}

# Leak-shaped fixtures assembled at runtime (split literals keep this file clean).
REAL_USER="victim"
PEM_HDR="-----BEGIN OPENSSH PRIVATE KE""Y-----"      # → real header only after eval
KEY_ANT="sk-ant-$(printf 'A%.0s' {1..30})"
KEY_GHP="ghp_$(printf 'b%.0s' {1..36})"

echo "=== test_check_no_secrets.sh ==="

# 1. Clean tree → pass
new_sandbox
put notes.md <<< "Just some ordinary documentation with no secrets."
scan; expect_rc "clean tree passes" 0
cleanup

# 2. Real macOS home path → fail
new_sandbox
put a.md <<< "config lives at /Users/$REAL_USER/src/app/config"
scan; expect_rc "real macOS home path fails" 1
expect_contains "reports home-path-macos" "home-path-macos"
cleanup

# 3. Placeholder-only home path → pass (allow-listed)
new_sandbox
put a.md <<< "put your project under /Users/you/project to follow along"
scan; expect_rc "placeholder /Users/you/ passes" 0
cleanup

# 4. CO-OCCURRENCE: real leak + placeholder on the SAME line → fail (the key case)
new_sandbox
put a.md <<< "real /Users/$REAL_USER/keys next to placeholder /Users/you/x"
scan; expect_rc "real+placeholder same line still fails" 1
expect_contains "co-occurrence reports the real leak" "$REAL_USER"
cleanup

# 5. Real Linux home path → fail
new_sandbox
put a.md <<< "logs under /home/$REAL_USER/var/log"
scan; expect_rc "real linux home path fails" 1
cleanup

# 6. Private-key header → fail
new_sandbox
put id.pem <<< "$PEM_HDR"
scan; expect_rc "private-key header fails" 1
expect_contains "reports private-key" "private-key"
cleanup

# 7. Anthropic key shape → fail
new_sandbox
put cfg.txt <<< "ANTHROPIC_API_KEY=$KEY_ANT"
scan; expect_rc "anthropic key shape fails" 1
cleanup

# 8. GitHub PAT shape → fail
new_sandbox
put cfg.txt <<< "token: $KEY_GHP"
scan; expect_rc "github pat shape fails" 1
cleanup

# 9. .secretsignore rule (user-segment granularity, like the real agricidaniel
#    rule) suppresses that user's paths → pass
new_sandbox
put a.md <<< "known-benign handle path /Users/$REAL_USER/build ok here"
put .secretsignore <<< "/(Users|home)/$REAL_USER/"
scan; expect_rc ".secretsignore rule suppresses the hit" 0
cleanup

# 9b. ...but a DIFFERENT real user on the same line is still caught
new_sandbox
put a.md <<< "benign /Users/$REAL_USER/x but also real /Users/attacker/loot"
put .secretsignore <<< "/(Users|home)/$REAL_USER/"
scan; expect_rc ".secretsignore allow does not mask a different real user" 1
expect_contains "still reports the non-allow-listed user" "attacker"
cleanup

# 10. Vendored plugin bundle excluded → pass despite a home path
new_sandbox
put .obsidian/plugins/some-plugin/main.js <<< "var p=\"/Users/$REAL_USER/lib/x.js\";"
put clean.md <<< "nothing to see"
scan; expect_rc "vendored .obsidian/plugins bundle excluded" 0
cleanup

echo ""
if [ "$FAILN" -gt 0 ]; then
  echo "check-no-secrets tests: $FAILN FAILED, $PASS passed."
  exit 1
fi
echo "All check-no-secrets tests passed ($PASS assertions)."
