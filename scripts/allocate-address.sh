#!/usr/bin/env bash
# allocate-address.sh — atomic creation-order address allocation for the vault.
#
# Reserves the next address of the form c-NNNNNN and increments the counter
# under an exclusive lock (flock where available; atomic-mkdir spinlock fallback
# on macOS/BSD, where flock is not installed). On missing counter file, recovers
# by scanning the vault for the highest existing c-NNNNNN in page frontmatter and
# resuming from max+1. Never silently resets to 1 in a non-empty vault.
#
# Usage:
#   ./scripts/allocate-address.sh           # prints the reserved address (e.g. c-000042) to stdout
#   ./scripts/allocate-address.sh --peek    # prints the next value without incrementing
#   ./scripts/allocate-address.sh --rebuild # recomputes counter from max observed and exits
#
# Exit codes:
#   0 — success
#   1 — lock acquisition failed (another writer is holding the lock)
#   2 — vault-meta directory missing and cannot be created
#   3 — counter value corrupt or non-numeric

set -euo pipefail

VAULT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COUNTER_FILE="${VAULT_ROOT}/.vault-meta/address-counter.txt"
LOCK_FILE="${VAULT_ROOT}/.vault-meta/.address.lock"
WIKI_DIR="${VAULT_ROOT}/wiki"

MODE="${1:-allocate}"

mkdir -p "$(dirname "$COUNTER_FILE")" || {
  echo "ERR: cannot create .vault-meta/" >&2
  exit 2
}

# Acquire an exclusive lock with a 5-second timeout.
# Prefer flock(1) where present (Linux); fall back to an atomic-mkdir spinlock on
# macOS/BSD, where flock is not installed. mkdir is atomic on POSIX filesystems —
# exactly one racer wins the create — so it is a correct portable mutex. flock
# auto-releases when the fd closes; the mkdir branch releases via an EXIT trap and
# reaps a mutex dir abandoned by a crashed allocator (older than 1 minute).
LOCK_MUTEX_DIR="${LOCK_FILE}.d"
if command -v flock >/dev/null 2>&1; then
  exec 9>"$LOCK_FILE"
  if ! flock -x -w 5 9; then
    echo "ERR: could not acquire address allocator lock within 5s" >&2
    exit 1
  fi
else
  _lock_deadline=$(( $(date +%s) + 5 ))
  until mkdir "$LOCK_MUTEX_DIR" 2>/dev/null; do
    # Reap a mutex dir abandoned by a crashed allocator (older than 1 minute).
    # TOCTOU note: a holder could release and a new racer re-acquire between this
    # age check and the rmdir, in which case we would reap a fresh lock. The window
    # is sub-millisecond and requires a >60s-old holder releasing in the exact gap;
    # acceptable under the single-tenant threat model (same trade-off as wiki-lock.sh).
    if [ -n "$(find "$LOCK_MUTEX_DIR" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
      rmdir "$LOCK_MUTEX_DIR" 2>/dev/null || true
      continue
    fi
    if [ "$(date +%s)" -ge "$_lock_deadline" ]; then
      echo "ERR: could not acquire address allocator lock within 5s" >&2
      exit 1
    fi
    sleep 0.2
  done
  trap 'rmdir "$LOCK_MUTEX_DIR" 2>/dev/null || true' EXIT
fi

scan_max_c_address() {
  # Emit the largest NNNNNN from "address: c-NNNNNN" lines that appear inside
  # the FIRST YAML frontmatter block of each wiki .md file. Code-block examples
  # and body prose are excluded. Returns 0 if none found.
  if [ ! -d "$WIKI_DIR" ]; then
    echo 0
    return
  fi
  # shellcheck disable=SC2016 # awk program is intentionally single-quoted
  find "$WIKI_DIR" -type f -name '*.md' -print0 2>/dev/null \
    | xargs -0 awk '
        FNR == 1 { state = "pre"; next_is_fm = ($0 == "---") ? 1 : 0 }
        FNR == 1 && $0 == "---" { state = "fm"; next }
        state == "fm" && $0 == "---" { state = "body"; nextfile }
        state == "fm" && match($0, /^address:[[:space:]]+c-[0-9]{6}[[:space:]]*$/) {
          if (match($0, /c-[0-9]{6}/)) {
            print substr($0, RSTART, RLENGTH)
          }
        }
      ' 2>/dev/null \
    | sed 's/^c-0*//;s/^$/0/' \
    | sort -n \
    | tail -1 \
    | awk 'BEGIN{n=0} {n=$0} END{print (n+0)}'
}

read_or_recover_counter() {
  if [ ! -f "$COUNTER_FILE" ]; then
    local max_c
    max_c="$(scan_max_c_address)"
    echo $((max_c + 1)) > "$COUNTER_FILE"
    echo "INFO: counter file missing; recovered from vault scan, set to $((max_c + 1))" >&2
  fi
  local raw
  raw="$(cat "$COUNTER_FILE")"
  if ! [[ "$raw" =~ ^[0-9]+$ ]]; then
    echo "ERR: counter file content is not a positive integer: $raw" >&2
    exit 3
  fi
  echo "$raw"
}

case "$MODE" in
  --peek)
    read_or_recover_counter
    ;;
  --rebuild)
    max_c="$(scan_max_c_address)"
    echo $((max_c + 1)) > "$COUNTER_FILE"
    echo "Counter rebuilt: next = $((max_c + 1))"
    ;;
  allocate|"")
    current="$(read_or_recover_counter)"
    next=$((current + 1))
    echo "$next" > "$COUNTER_FILE"
    printf 'c-%06d\n' "$current"
    ;;
  *)
    echo "ERR: unknown mode: $MODE" >&2
    echo "Usage: $0 [allocate|--peek|--rebuild]" >&2
    exit 3
    ;;
esac
