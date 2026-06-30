#!/usr/bin/env bash
# Download URL to a temporary sibling, verify SHA-256, then atomically install.
set -euo pipefail

[ $# -eq 3 ] || { echo "Usage: $0 URL SHA256 DESTINATION" >&2; exit 2; }
URL="$1"
EXPECTED="$2"
DEST="$3"
mkdir -p "$(dirname "$DEST")"
TMP="${DEST}.download.$$"
trap 'rm -f "$TMP"' EXIT

curl --fail --location --silent --show-error "$URL" -o "$TMP"
if command -v shasum >/dev/null 2>&1; then
  ACTUAL="$(shasum -a 256 "$TMP" | awk '{print $1}')"
elif command -v sha256sum >/dev/null 2>&1; then
  ACTUAL="$(sha256sum "$TMP" | awk '{print $1}')"
else
  echo "ERR: no SHA-256 utility found; refusing unverified download" >&2
  exit 4
fi
[ "$ACTUAL" = "$EXPECTED" ] || {
  echo "ERR: checksum mismatch for $URL" >&2
  exit 4
}
mv "$TMP" "$DEST"
trap - EXIT
