#!/usr/bin/env python3
"""test_check_version_sync.py — hermetic tests for scripts/check-version-sync.py.

Covers the pure drift logic, the CHANGELOG heading parser (incl. skipping
"## [Unreleased]"), the missing/unparseable -> exit-2 path, and the --check-tag
gate (git is mocked). All fixtures are built in a temp dir; the real repo is
never read. No network, no third-party deps. Pure stdlib.

Usage:
  python3 tests/test_check_version_sync.py
"""
import contextlib
import importlib.util
import io
import json
import tempfile
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent
HELPER = ROOT / "scripts" / "check-version-sync.py"

spec = importlib.util.spec_from_file_location("check_version_sync", HELPER)
cvs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cvs)


class Fail(SystemExit):
    pass


def assert_eq(label, expected, actual):
    if expected != actual:
        raise Fail(f"FAIL {label}: expected {expected!r}, got {actual!r}")
    print(f"OK   {label}")


def assert_true(label, cond, hint=""):
    if not cond:
        raise Fail(f"FAIL {label}{(': ' + hint) if hint else ''}")
    print(f"OK   {label}")


def assert_raises(label, exc_type, fn):
    try:
        fn()
    except exc_type:
        print(f"OK   {label}")
        return
    raise Fail(f"FAIL {label}: expected {exc_type.__name__}")


def write_fixture(root, plugin_v="1.2.3", meta_v=None, entry_vs=None,
                  changelog_v=None, with_unreleased=False):
    """Build a minimal vault layout. Unspecified versions default to plugin_v
    so the in-sync case needs no boilerplate."""
    meta_v = plugin_v if meta_v is None else meta_v
    entry_vs = [plugin_v] if entry_vs is None else entry_vs
    changelog_v = plugin_v if changelog_v is None else changelog_v

    (root / ".claude-plugin").mkdir(parents=True, exist_ok=True)
    (root / ".claude-plugin" / "plugin.json").write_text(
        json.dumps({"name": "x", "version": plugin_v}))
    (root / ".claude-plugin" / "marketplace.json").write_text(json.dumps({
        "metadata": {"version": meta_v},
        "plugins": [{"name": "x", "version": v} for v in entry_vs],
    }))
    body = "# Changelog\n\n"
    if with_unreleased:
        body += "## [Unreleased]\n\n### Added\n- pending\n\n"
    body += f"## [{changelog_v}] - 2026-01-01\n\nnotes\n"
    (root / "CHANGELOG.md").write_text(body)


# ─── Pure drift logic ────────────────────────────────────────────────────────
def test_in_sync_passes():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        write_fixture(root)
        ok, canonical, offenders = cvs.evaluate(cvs.collect_hard_surfaces(root))
        assert_true("in-sync → ok", ok)
        assert_eq("canonical version", "1.2.3", canonical)
        assert_eq("no offenders", {}, offenders)


def test_marketplace_metadata_drift_detected():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        write_fixture(root, meta_v="9.9.9")
        ok, _, offenders = cvs.evaluate(cvs.collect_hard_surfaces(root))
        assert_true("metadata drift → not ok", not ok)
        assert_true("metadata flagged",
                    "marketplace.json:metadata.version" in offenders)


def test_plugin_entry_drift_detected():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        write_fixture(root, entry_vs=["1.2.3", "1.2.4"])
        ok, _, offenders = cvs.evaluate(cvs.collect_hard_surfaces(root))
        assert_true("entry drift → not ok", not ok)
        assert_true("second entry flagged",
                    "marketplace.json:plugins[1].version" in offenders)


def test_changelog_drift_detected():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        write_fixture(root, changelog_v="2.0.0")
        ok, _, offenders = cvs.evaluate(cvs.collect_hard_surfaces(root))
        assert_true("changelog drift → not ok", not ok)
        assert_true("changelog flagged", "CHANGELOG.md:top-heading" in offenders)


# ─── CHANGELOG parser ────────────────────────────────────────────────────────
def test_changelog_skips_unreleased_heading():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        write_fixture(root, with_unreleased=True)
        surfaces = cvs.read_changelog_version(root)
        assert_eq("[Unreleased] skipped, picks numeric heading",
                  "1.2.3", surfaces["CHANGELOG.md:top-heading"])


# ─── Missing / unparseable surfaces ──────────────────────────────────────────
def test_missing_plugin_json_raises():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        write_fixture(root)
        (root / ".claude-plugin" / "plugin.json").unlink()
        assert_raises("missing plugin.json raises",
                      cvs.VersionSyncError, lambda: cvs.collect_hard_surfaces(root))


def test_unparseable_marketplace_raises():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        write_fixture(root)
        (root / ".claude-plugin" / "marketplace.json").write_text("{ not json")
        assert_raises("unparseable marketplace.json raises",
                      cvs.VersionSyncError, lambda: cvs.collect_hard_surfaces(root))


# ─── main() exit codes (ROOT patched to the fixture) ─────────────────────────
def _main_rc(root, argv):
    with mock.patch.object(cvs, "ROOT", root), \
         contextlib.redirect_stderr(io.StringIO()), \
         contextlib.redirect_stdout(io.StringIO()):
        return cvs.main(argv)


def test_main_returns_0_in_sync():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        write_fixture(root)
        assert_eq("main rc=0 when in sync", cvs.EXIT_OK, _main_rc(root, []))


def test_main_returns_1_on_drift():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        write_fixture(root, changelog_v="2.0.0")
        assert_eq("main rc=1 on drift", cvs.EXIT_DRIFT, _main_rc(root, []))


def test_main_returns_2_when_unreadable():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        write_fixture(root)
        (root / "CHANGELOG.md").unlink()
        assert_eq("main rc=2 when a surface is missing",
                  cvs.EXIT_UNREADABLE, _main_rc(root, []))


# ─── --check-tag gate (git mocked) ───────────────────────────────────────────
def _fake_git(rc, stdout="", stderr=""):
    def runner(cmd, cwd=None, capture_output=None, text=None):
        return mock.Mock(returncode=rc, stdout=stdout, stderr=stderr)
    return runner


def test_check_tag_matches_returns_0():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        write_fixture(root)
        with mock.patch.object(cvs.subprocess, "run", _fake_git(0, "v1.2.3\n")):
            assert_eq("tag matches → rc=0", cvs.EXIT_OK, _main_rc(root, ["--check-tag"]))


def test_check_tag_mismatch_returns_1():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        write_fixture(root)
        with mock.patch.object(cvs.subprocess, "run", _fake_git(0, "v1.2.2\n")):
            assert_eq("tag mismatch → rc=1", cvs.EXIT_DRIFT,
                      _main_rc(root, ["--check-tag"]))


def test_check_tag_no_tags_returns_2():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        write_fixture(root)
        with mock.patch.object(cvs.subprocess, "run", _fake_git(128, "", "fatal: no names")):
            assert_eq("no tags → rc=2", cvs.EXIT_UNREADABLE,
                      _main_rc(root, ["--check-tag"]))


def main():
    print("=== test_check_version_sync.py ===")
    test_in_sync_passes()
    test_marketplace_metadata_drift_detected()
    test_plugin_entry_drift_detected()
    test_changelog_drift_detected()
    test_changelog_skips_unreleased_heading()
    test_missing_plugin_json_raises()
    test_unparseable_marketplace_raises()
    test_main_returns_0_in_sync()
    test_main_returns_1_on_drift()
    test_main_returns_2_when_unreadable()
    test_check_tag_matches_returns_0()
    test_check_tag_mismatch_returns_1()
    test_check_tag_no_tags_returns_2()
    print("\nAll check-version-sync tests passed.")


if __name__ == "__main__":
    main()
