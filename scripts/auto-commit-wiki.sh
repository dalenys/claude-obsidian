#!/usr/bin/env bash
# Stage and commit completed vault mutations once all per-file leases are released.
set -euo pipefail

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  exit 0
fi
REPO_ROOT="$(git rev-parse --show-toplevel)" || exit 0
cd "$REPO_ROOT"

report_failure() {
  local message="$1"
  mkdir -p .vault-meta 2>/dev/null || true
  printf '%s %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$message" \
    >> .vault-meta/hook.log 2>/dev/null || true
  printf 'ERR: %s\n' "$message" >&2
}

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
if ! git add -- wiki/ .raw/ .vault-meta/ 2>/dev/null; then
  report_failure "wiki auto-commit staging failed"
  exit 1
fi
STAGED=()
while IFS= read -r -d '' path; do
  STAGED+=("$path")
done < <(git diff --cached --name-only -z -- wiki/ .raw/ .vault-meta/)
[ ${#STAGED[@]} -gt 0 ] || exit 0
if ! git commit -m "wiki: auto-commit $(date '+%Y-%m-%d %H:%M')" \
  -- "${STAGED[@]}"; then
  report_failure "wiki auto-commit commit failed; staged changes preserved"
  exit 1
fi
