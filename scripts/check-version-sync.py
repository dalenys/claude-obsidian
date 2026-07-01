#!/usr/bin/env python3
"""check-version-sync.py — assert the plugin version is identical across every
machine-readable surface, so a release can never ship with drifted manifests.

This automates the manual cross-check the audits perform by hand at every
release (the recurring `chore(vN): version sync` ritual; audit finding M16).

Hard gate — these must agree exactly or the check fails:
  - .claude-plugin/plugin.json        -> version
  - .claude-plugin/marketplace.json   -> metadata.version
  - .claude-plugin/marketplace.json   -> plugins[i].version (every entry)
  - CHANGELOG.md                      -> top-most "## [X.Y.Z]" heading
                                         (a "## [Unreleased]" heading is skipped)

Soft surfaces (warn only, opt-in via --warn-soft): README.md and
docs/install-guide.md carry the version in prose plus a dynamic shields.io
badge, which makes an exact-match gate false-positive-prone. They are reported,
never fatal.

With --check-tag (release gate only): also require the latest git tag
(`git describe --tags --abbrev=0`, leading "v" stripped) to equal the manifest
version. Off by default because manifests are legitimately bumped *before* the
tag is cut mid-development, so the everyday `make test` path must not depend on
tags existing.

Exit codes:
  0  all hard surfaces agree (and the tag matches, when --check-tag)
  1  drift detected among hard surfaces (or tag mismatch under --check-tag)
  2  a surface is missing/unparseable, or the tag cannot be determined

No network, no third-party dependencies. Pure stdlib.

Usage:
  python3 scripts/check-version-sync.py
  python3 scripts/check-version-sync.py --check-tag
  python3 scripts/check-version-sync.py --warn-soft
"""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

EXIT_OK = 0
EXIT_DRIFT = 1
EXIT_UNREADABLE = 2

# First "## [X.Y.Z]" heading with a numeric semver — naturally skips "[Unreleased]".
CHANGELOG_HEADING = re.compile(r"^##\s*\[(\d+\.\d+\.\d+)\]", re.MULTILINE)


class VersionSyncError(Exception):
    """A surface is missing or could not be parsed — distinct from version drift."""


# ─── Surface readers ─────────────────────────────────────────────────────────
def _load_json(path: Path) -> dict:
    if not path.exists():
        raise VersionSyncError(f"{path}: missing")
    try:
        return json.loads(path.read_text())
    except (json.JSONDecodeError, OSError) as exc:
        raise VersionSyncError(f"{path}: not parseable ({exc})") from exc


def read_plugin_version(root: Path) -> dict:
    data = _load_json(root / ".claude-plugin" / "plugin.json")
    v = data.get("version")
    if not v:
        raise VersionSyncError(".claude-plugin/plugin.json: no 'version' field")
    return {"plugin.json:version": v}


def read_marketplace_versions(root: Path) -> dict:
    data = _load_json(root / ".claude-plugin" / "marketplace.json")
    out = {}
    meta_v = (data.get("metadata") or {}).get("version")
    if not meta_v:
        raise VersionSyncError("marketplace.json: no 'metadata.version' field")
    out["marketplace.json:metadata.version"] = meta_v
    plugins = data.get("plugins") or []
    if not plugins:
        raise VersionSyncError("marketplace.json: no 'plugins' entries")
    for i, plugin in enumerate(plugins):
        v = plugin.get("version")
        if not v:
            raise VersionSyncError(f"marketplace.json: plugins[{i}] has no 'version'")
        out[f"marketplace.json:plugins[{i}].version"] = v
    return out


def read_changelog_version(root: Path) -> dict:
    path = root / "CHANGELOG.md"
    if not path.exists():
        raise VersionSyncError("CHANGELOG.md: missing")
    m = CHANGELOG_HEADING.search(path.read_text())
    if not m:
        raise VersionSyncError("CHANGELOG.md: no '## [X.Y.Z]' versioned heading found")
    return {"CHANGELOG.md:top-heading": m.group(1)}


def collect_hard_surfaces(root: Path) -> dict:
    """Return {surface_label: version_string} for every hard-gate surface."""
    surfaces = {}
    surfaces.update(read_plugin_version(root))
    surfaces.update(read_marketplace_versions(root))
    surfaces.update(read_changelog_version(root))
    return surfaces


# ─── Pure comparison ─────────────────────────────────────────────────────────
def evaluate(surfaces: dict):
    """Pure: pick the canonical version (plugin.json is the source of truth) and
    list the labels that disagree with it. Returns (ok, canonical, offenders)."""
    canonical = surfaces["plugin.json:version"]
    offenders = {
        label: ver for label, ver in surfaces.items() if ver != canonical
    }
    return (not offenders, canonical, offenders)


# ─── Soft surfaces + tag (side checks, not part of the pure core) ────────────
def soft_surface_versions(root: Path) -> dict:
    """Best-effort scan of prose surfaces. Returns {label: [versions found]}.
    Never raises; missing files are simply skipped."""
    found = {}
    semver = re.compile(r"\b(\d+\.\d+\.\d+)\b")
    for rel in ("README.md", "docs/install-guide.md"):
        path = root / rel
        if not path.exists():
            continue
        hits = sorted(set(semver.findall(path.read_text())))
        found[rel] = hits
    return found


def latest_git_tag(root: Path) -> str:
    """Latest tag with the leading 'v' stripped. Raises VersionSyncError if git
    has no tags or is unavailable — a release gate must fail loudly here."""
    try:
        out = subprocess.run(
            ["git", "describe", "--tags", "--abbrev=0"],
            cwd=root, capture_output=True, text=True,
        )
    except FileNotFoundError as exc:
        raise VersionSyncError("git not available to resolve latest tag") from exc
    if out.returncode != 0:
        raise VersionSyncError(
            f"could not determine latest git tag: {out.stderr.strip() or 'no tags'}"
        )
    return out.stdout.strip().lstrip("v")


# ─── CLI ─────────────────────────────────────────────────────────────────────
def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Assert plugin version is in sync.")
    parser.add_argument("--check-tag", action="store_true",
                        help="also require the latest git tag to match (release gate)")
    parser.add_argument("--warn-soft", action="store_true",
                        help="also report README/install-guide versions (non-fatal)")
    args = parser.parse_args(argv)

    try:
        surfaces = collect_hard_surfaces(ROOT)
    except VersionSyncError as exc:
        print(f"version-sync: UNREADABLE — {exc}", file=sys.stderr)
        return EXIT_UNREADABLE

    ok, canonical, offenders = evaluate(surfaces)
    if not ok:
        print("version-sync: DRIFT — surfaces disagree on the plugin version.",
              file=sys.stderr)
        print(f"  canonical (plugin.json): {canonical}", file=sys.stderr)
        for label, ver in sorted(offenders.items()):
            print(f"  DRIFT {label}: {ver}", file=sys.stderr)
        return EXIT_DRIFT

    if args.check_tag:
        try:
            tag = latest_git_tag(ROOT)
        except VersionSyncError as exc:
            print(f"version-sync: UNREADABLE — {exc}", file=sys.stderr)
            return EXIT_UNREADABLE
        if tag != canonical:
            print("version-sync: DRIFT — latest git tag disagrees with manifests.",
                  file=sys.stderr)
            print(f"  manifests: {canonical}", file=sys.stderr)
            print(f"  git tag:   {tag}", file=sys.stderr)
            return EXIT_DRIFT

    if args.warn_soft:
        for rel, hits in soft_surface_versions(ROOT).items():
            stray = [h for h in hits if h != canonical]
            if stray:
                print(f"version-sync: note — {rel} also mentions {stray} "
                      f"(soft surface, not gated)")

    tag_note = " + git tag" if args.check_tag else ""
    print(f"version-sync: OK — all {len(surfaces)} surfaces{tag_note} agree on {canonical}.")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
