#!/usr/bin/env bash
# Stage and commit completed vault mutations once all per-file leases are released.
set -euo pipefail

[ -d .git ] || exit 0
[ ! -f .vault-meta/auto-commit.disabled ] || exit 0
if [ -x scripts/wiki-lock.sh ]; then
  if ! LOCK_LIST="$(bash scripts/wiki-lock.sh list 2>/dev/null)"; then
    mkdir -p .vault-meta 2>/dev/null || true
    printf '%s wiki-lock list failed; deferred auto-commit\n' \
      "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" >> .vault-meta/hook.log 2>/dev/null || true
    exit 0
  fi
  [ -z "$LOCK_LIST" ] || exit 0
fi
git add -- wiki/ .raw/ .vault-meta/ 2>/dev/null || exit 0
STAGED=()
while IFS= read -r -d '' path; do
  STAGED+=("$path")
done < <(git diff --cached --name-only -z -- wiki/ .raw/ .vault-meta/)
[ ${#STAGED[@]} -gt 0 ] || exit 0
git commit -m "wiki: auto-commit $(date '+%Y-%m-%d %H:%M')" \
  -- "${STAGED[@]}" 2>/dev/null || true
