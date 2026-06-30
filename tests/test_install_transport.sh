#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASS=0
FAIL=0
ok() { echo "OK   $1"; PASS=$((PASS + 1)); }
bad() { echo "FAIL $1${2:+: $2}"; FAIL=$((FAIL + 1)); }

TMP=$(mktemp -d /tmp/claude-obsidian-audit-XXXXXX)
trap 'rm -rf "$TMP"' EXIT

# DragonScale rebuilds a missing counter from existing addressed pages.
V="$TMP/dragon"
mkdir -p "$V/bin" "$V/scripts" "$V/skills/wiki-fold" "$V/wiki"
cp "$ROOT/bin/setup-dragonscale.sh" "$V/bin/"
cp "$ROOT/scripts/allocate-address.sh" "$V/scripts/"
cp "$ROOT/scripts/tiling-check.py" "$V/scripts/"
: > "$V/skills/wiki-fold/SKILL.md"
printf '%s\n' '---' 'address: c-000041' '---' > "$V/wiki/existing.md"
bash "$V/bin/setup-dragonscale.sh" "$V" >/dev/null 2>&1
[ "$(cat "$V/.vault-meta/address-counter.txt")" = 42 ] &&
  ok "DragonScale counter resumes at 42" || bad "DragonScale counter resumes at 42"

# Vault setup is non-destructive by default and forced replacement creates backup.
V="$TMP/vault"
mkdir -p "$V/bin" "$V/.obsidian"
cp "$ROOT/bin/setup-vault.sh" "$V/bin/"
printf 'custom\n' > "$V/.obsidian/graph.json"
bash "$V/bin/setup-vault.sh" "$V" >/dev/null
[ "$(cat "$V/.obsidian/graph.json")" = custom ] &&
  ok "setup preserves existing Obsidian JSON" || bad "setup preserves existing Obsidian JSON"
bash "$V/bin/setup-vault.sh" --force "$V" >/dev/null
if [ "$(cat "$V/.obsidian/graph.json")" != custom ] &&
   find "$V/.obsidian" -name 'graph.json.backup-*' | grep -q .; then
  ok "forced setup replaces and backs up JSON"
else
  bad "forced setup replaces and backs up JSON"
fi

# CLI capability detection rejects a name collision and accepts expected commands.
V="$TMP/transport"
mkdir -p "$V/scripts" "$V/fake"
cp "$ROOT/scripts/detect-transport.sh" "$V/scripts/"
cat > "$V/fake/obsidian-cli" <<'SH'
#!/usr/bin/env bash
echo "unrelated obsidian-cli 1.0"
SH
chmod +x "$V/fake/obsidian-cli"
OUT=$(PATH="$V/fake:/usr/bin:/bin" bash "$V/scripts/detect-transport.sh" --peek)
python3 -c 'import json,sys; assert json.load(sys.stdin)["preferred"] == "filesystem"' <<<"$OUT" &&
  ok "incompatible obsidian-cli rejected" || bad "incompatible obsidian-cli rejected"
cat > "$V/fake/obsidian-cli" <<'SH'
#!/usr/bin/env bash
case "$1" in
  --help) echo "read write append search daily:today daily:append property:set backlinks bases tags bookmarks" ;;
  --version) echo "obsidian-cli 1.12" ;;
esac
SH
chmod +x "$V/fake/obsidian-cli"
OUT=$(PATH="$V/fake:/usr/bin:/bin" bash "$V/scripts/detect-transport.sh" --peek)
python3 -c 'import json,sys; assert json.load(sys.stdin)["preferred"] == "cli"' <<<"$OUT" &&
  ok "compatible obsidian-cli accepted" || bad "compatible obsidian-cli accepted"

# Complete snapshot encoding handles quote-bearing vault paths.
Q="$TMP/vault\"quoted"
mkdir -p "$Q/scripts"
cp "$ROOT/scripts/detect-transport.sh" "$Q/scripts/"
OUT=$(PATH="/usr/bin:/bin" bash "$Q/scripts/detect-transport.sh" --peek)
python3 -c 'import json,sys; d=json.load(sys.stdin); assert "\"" in d["vault_root"]' <<<"$OUT" &&
  ok "transport JSON escapes vault path" || bad "transport JSON escapes vault path"

OLLAMA_URL=http://remote.example:11434 bash "$ROOT/bin/setup-retrieve.sh" \
  --allow-remote-ollama --check >/dev/null 2>&1
[ $? -eq 0 ] && ok "remote Ollama consent flag parses" || bad "remote Ollama consent flag parses"

# Verified downloader fails closed and installs atomically.
mkdir -p "$TMP/download/bin"
printf 'verified payload\n' > "$TMP/download/source"
EXPECTED=$(shasum -a 256 "$TMP/download/source" | awk '{print $1}')
cat > "$TMP/download/bin/curl" <<SH
#!/usr/bin/env bash
out=""
while [ \$# -gt 0 ]; do
  [ "\$1" = "-o" ] && { out="\$2"; shift 2; continue; }
  shift
done
cp "$TMP/download/source" "\$out"
SH
chmod +x "$TMP/download/bin/curl"
PATH="$TMP/download/bin:/usr/bin:/bin" bash "$ROOT/scripts/install-verified-download.sh" \
  https://example.invalid/file "$EXPECTED" "$TMP/download/dest"
[ "$(cat "$TMP/download/dest" 2>/dev/null)" = "verified payload" ] &&
  ok "verified downloader installs matching payload" || bad "verified downloader installs matching payload"
printf 'keep\n' > "$TMP/download/dest"
PATH="$TMP/download/bin:/usr/bin:/bin" bash "$ROOT/scripts/install-verified-download.sh" \
  https://example.invalid/file deadbeef "$TMP/download/dest" >/dev/null 2>&1
[ $? -ne 0 ] && [ "$(cat "$TMP/download/dest")" = keep ] &&
  ok "checksum mismatch preserves destination" || bad "checksum mismatch preserves destination"
cat > "$TMP/download/bin/curl" <<'SH'
#!/usr/bin/env bash
exit 22
SH
PATH="$TMP/download/bin:/usr/bin:/bin" bash "$ROOT/scripts/install-verified-download.sh" \
  https://example.invalid/file "$EXPECTED" "$TMP/download/dest" >/dev/null 2>&1
[ $? -ne 0 ] && [ "$(cat "$TMP/download/dest")" = keep ] &&
  ok "download failure preserves destination" || bad "download failure preserves destination"

python3 - "$ROOT" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
hook = json.loads((root / "hooks/hooks.json").read_text())
command = hook["hooks"]["PostToolUse"][0]["hooks"][0]["command"]
assert "scripts/auto-commit-wiki.sh" in command
for skill in ("save", "autoresearch", "wiki-query"):
    header = (root / "skills" / skill / "SKILL.md").read_text().split("---", 2)[1]
    assert "Bash" in header, skill
for skill in ("save", "autoresearch", "wiki-ingest", "wiki-fold"):
    text = (root / "skills" / skill / "SKILL.md").read_text()
    assert "bash scripts/auto-commit-wiki.sh" in text, skill
ingest = (root / "skills/wiki-ingest/SKILL.md").read_text()
assert "shasum -a 256" in ingest and "command -v shasum" in ingest
PY
[ $? -eq 0 ] && ok "hook and skill contracts are complete" || bad "hook and skill contracts are complete"

# A write deferred under a lock is committed after the final release.
V="$TMP/commit"
mkdir -p "$V/scripts" "$V/wiki" "$V/.raw"
cp "$ROOT/scripts/wiki-lock.sh" "$ROOT/scripts/auto-commit-wiki.sh" "$V/scripts/"
git -C "$V" init -q
git -C "$V" config user.name Test
git -C "$V" config user.email test@example.invalid
touch "$V/wiki/.keep" "$V/.raw/.keep"
git -C "$V" add .
git -C "$V" commit -qm seed
(
  cd "$V" || exit
  bash scripts/wiki-lock.sh acquire wiki/note.md
  printf 'content\n' > wiki/note.md
  bash scripts/auto-commit-wiki.sh
  [ "$(git rev-list --count HEAD)" -eq 1 ] || exit 1
  bash scripts/wiki-lock.sh release wiki/note.md
  bash scripts/auto-commit-wiki.sh
  [ "$(git rev-list --count HEAD)" -eq 2 ]
)
[ $? -eq 0 ] && ok "post-release helper completes deferred commit" ||
  bad "post-release helper completes deferred commit"

echo "Pass: $PASS  Fail: $FAIL"
[ "$FAIL" -eq 0 ]
