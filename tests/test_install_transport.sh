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
if [ "$(cat "$V/.vault-meta/address-counter.txt")" = 42 ]; then
  ok "DragonScale counter resumes at 42"
else
  bad "DragonScale counter resumes at 42"
fi

# Vault setup is non-destructive by default and forced replacement creates backup.
V="$TMP/vault"
mkdir -p "$V/bin" "$V/.obsidian"
cp "$ROOT/bin/setup-vault.sh" "$V/bin/"
for config in graph app appearance; do
  printf 'custom-%s\n' "$config" > "$V/.obsidian/$config.json"
done
bash "$V/bin/setup-vault.sh" "$V" >/dev/null
for config in graph app appearance; do
  if [ "$(cat "$V/.obsidian/$config.json")" = "custom-$config" ]; then
    ok "setup preserves existing $config.json"
  else
    bad "setup preserves existing $config.json"
  fi
done
bash "$V/bin/setup-vault.sh" --force "$V" >/dev/null
for config in graph app appearance; do
  if [ "$(cat "$V/.obsidian/$config.json")" != "custom-$config" ] &&
     find "$V/.obsidian" -name "$config.json.backup-*" | grep -q .; then
    ok "forced setup replaces and backs up $config.json"
  else
    bad "forced setup replaces and backs up $config.json"
  fi
done

# CLI capability detection rejects a name collision and accepts expected commands.
V="$TMP/transport"
mkdir -p "$V/scripts" "$V/fake"
cp "$ROOT/scripts/detect-transport.sh" "$V/scripts/"
cat > "$V/fake/obsidian-cli" <<'SH'
#!/usr/bin/env bash
if [ "$1" = "--help" ]; then
  echo "Documentation says read write append search daily:today daily:append property:set backlinks bases tags bookmarks."
  exit 0
fi
exit 2
SH
chmod +x "$V/fake/obsidian-cli"
OUT=$(PATH="$V/fake:/usr/bin:/bin" bash "$V/scripts/detect-transport.sh" --peek)
if python3 -c 'import json,sys; assert json.load(sys.stdin)["preferred"] == "filesystem"' <<<"$OUT"; then
  ok "prose-only obsidian-cli rejected"
else
  bad "prose-only obsidian-cli rejected"
fi
cat > "$V/fake/obsidian-cli" <<'SH'
#!/usr/bin/env bash
case "$1" in
  --version) echo "obsidian-cli 1.12"; exit 0 ;;
  read|write|append|search|daily:today|daily:append|property:set|backlinks|bases|tags|bookmarks)
    [ "${2:-}" = "--help" ] && exit 0
    ;;
esac
exit 2
SH
chmod +x "$V/fake/obsidian-cli"
OUT=$(PATH="$V/fake:/usr/bin:/bin" bash "$V/scripts/detect-transport.sh" --peek)
if python3 -c 'import json,sys; assert json.load(sys.stdin)["preferred"] == "cli"' <<<"$OUT"; then
  ok "compatible obsidian-cli accepted"
else
  bad "compatible obsidian-cli accepted"
fi
cat > "$V/fake/obsidian-cli" <<'SH'
#!/usr/bin/env bash
case "$1" in
  --version) exit 0 ;;
  read|write|append|search|daily:today|daily:append|property:set|backlinks|bases|tags)
    [ "${2:-}" = "--help" ] && exit 0
    ;;
esac
exit 2
SH
chmod +x "$V/fake/obsidian-cli"
OUT=$(PATH="$V/fake:/usr/bin:/bin" bash "$V/scripts/detect-transport.sh" --peek)
if python3 -c 'import json,sys; assert json.load(sys.stdin)["preferred"] == "filesystem"' <<<"$OUT"; then
  ok "obsidian-cli missing one required command is rejected"
else
  bad "obsidian-cli missing one required command is rejected"
fi
rm "$V/fake/obsidian-cli"
cat > "$V/fake/obsidian" <<'SH'
#!/usr/bin/env bash
case "$1" in
  --version) echo "Obsidian 1.12"; exit 0 ;;
  read|write|append|search|daily:today|daily:append|property:set|backlinks|bases|tags|bookmarks)
    [ "${2:-}" = "--help" ] && exit 0
    ;;
esac
exit 2
SH
chmod +x "$V/fake/obsidian"
OUT=$(PATH="$V/fake:/usr/bin:/bin" bash "$V/scripts/detect-transport.sh" --peek)
if python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["preferred"] == "cli"; assert d["available"]["cli"]["binary"] == "obsidian"' <<<"$OUT"; then
  ok "official obsidian binary remains supported"
else
  bad "official obsidian binary remains supported"
fi

# Complete snapshot encoding handles quote-bearing vault paths.
Q="$TMP/vault\"quoted"
mkdir -p "$Q/scripts"
cp "$ROOT/scripts/detect-transport.sh" "$Q/scripts/"
OUT=$(PATH="/usr/bin:/bin" bash "$Q/scripts/detect-transport.sh" --peek)
if python3 -c 'import json,sys; d=json.load(sys.stdin); assert "\"" in d["vault_root"]' <<<"$OUT"; then
  ok "transport JSON escapes vault path"
else
  bad "transport JSON escapes vault path"
fi

mkdir -p "$TMP/ollama/bin"
CURL_LOG="$TMP/ollama/curl.log"
cat > "$TMP/ollama/bin/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_LOG"
printf '{"models":[]}\n'
SH
chmod +x "$TMP/ollama/bin/curl"
if CURL_LOG="$CURL_LOG" PATH="$TMP/ollama/bin:/opt/homebrew/bin:/usr/bin:/bin" \
   OLLAMA_URL=http://remote.example:11434 bash "$ROOT/bin/setup-retrieve.sh" \
   --allow-remote-ollama --check >/dev/null 2>&1 &&
   grep -q 'http://remote.example:11434/api/tags' "$CURL_LOG"; then
  ok "remote Ollama consent invokes configured URL"
else
  bad "remote Ollama consent invokes configured URL"
fi
: > "$CURL_LOG"
CURL_LOG="$CURL_LOG" PATH="$TMP/ollama/bin:/opt/homebrew/bin:/usr/bin:/bin" \
  OLLAMA_URL=http://remote.example:11434 bash "$ROOT/bin/setup-retrieve.sh" \
  --check >/dev/null 2>&1
if [ ! -s "$CURL_LOG" ]; then
  ok "remote Ollama without consent is not invoked"
else
  bad "remote Ollama without consent is not invoked"
fi

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
if [ "$(cat "$TMP/download/dest" 2>/dev/null)" = "verified payload" ]; then
  ok "verified downloader installs matching payload"
else
  bad "verified downloader installs matching payload"
fi
printf 'keep\n' > "$TMP/download/dest"
if ! PATH="$TMP/download/bin:/usr/bin:/bin" bash "$ROOT/scripts/install-verified-download.sh" \
  https://example.invalid/file deadbeef "$TMP/download/dest" >/dev/null 2>&1 &&
  [ "$(cat "$TMP/download/dest")" = keep ]; then
  ok "checksum mismatch preserves destination"
else
  bad "checksum mismatch preserves destination"
fi
cat > "$TMP/download/bin/curl" <<'SH'
#!/usr/bin/env bash
exit 22
SH
if ! PATH="$TMP/download/bin:/usr/bin:/bin" bash "$ROOT/scripts/install-verified-download.sh" \
  https://example.invalid/file "$EXPECTED" "$TMP/download/dest" >/dev/null 2>&1 &&
  [ "$(cat "$TMP/download/dest")" = keep ]; then
  ok "download failure preserves destination"
else
  bad "download failure preserves destination"
fi

if python3 - "$ROOT" <<'PY'
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
assert "bash scripts/auto-commit-wiki.sh" in (root / "agents/wiki-ingest.md").read_text()
ingest = (root / "skills/wiki-ingest/SKILL.md").read_text()
assert "shasum -a 256" in ingest and "command -v shasum" in ingest
PY
then
  ok "hook and skill contracts are complete"
else
  bad "hook and skill contracts are complete"
fi

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
if (
  cd "$V" || exit
  bash scripts/wiki-lock.sh acquire wiki/note.md
  printf 'content\n' > wiki/note.md
  bash scripts/auto-commit-wiki.sh
  [ "$(git rev-list --count HEAD)" -eq 1 ] || exit 1
  bash scripts/wiki-lock.sh release wiki/note.md
  bash scripts/auto-commit-wiki.sh
  [ "$(git rev-list --count HEAD)" -eq 2 ]
); then
  ok "post-release helper completes deferred commit"
else
  bad "post-release helper completes deferred commit"
fi

cat > "$V/.git/hooks/pre-commit" <<'SH'
#!/usr/bin/env bash
exit 1
SH
chmod +x "$V/.git/hooks/pre-commit"
printf 'will remain staged\n' > "$V/wiki/failing.md"
if ! (cd "$V" && bash scripts/auto-commit-wiki.sh) \
     >"$TMP/commit-failure.stdout" 2>"$TMP/commit-failure.stderr" &&
   grep -q 'wiki auto-commit commit failed' "$TMP/commit-failure.stderr" &&
   grep -q 'wiki auto-commit commit failed' "$V/.vault-meta/hook.log" &&
   git -C "$V" diff --cached --name-only | grep -q '^wiki/failing.md$'; then
  ok "auto-commit surfaces and logs commit failure"
else
  bad "auto-commit surfaces and logs commit failure"
fi

# Linked worktrees store .git as a file; the helper must still commit at that root.
V="$TMP/worktree-source"
W="$TMP/worktree-linked"
mkdir -p "$V/scripts" "$V/wiki" "$V/.raw"
cp "$ROOT/scripts/wiki-lock.sh" "$ROOT/scripts/auto-commit-wiki.sh" "$V/scripts/"
git -C "$V" init -q
git -C "$V" config user.name Test
git -C "$V" config user.email test@example.invalid
touch "$V/wiki/.keep" "$V/.raw/.keep"
git -C "$V" add .
git -C "$V" commit -qm seed
git -C "$V" worktree add -qb test-linked "$W"
printf 'linked content\n' > "$W/wiki/linked.md"
if (cd "$W" && bash scripts/auto-commit-wiki.sh) &&
   [ "$(git -C "$W" rev-list --count HEAD)" -eq 2 ]; then
  ok "auto-commit works in linked worktree"
else
  bad "auto-commit works in linked worktree"
fi

echo "Pass: $PASS  Fail: $FAIL"
[ "$FAIL" -eq 0 ]
