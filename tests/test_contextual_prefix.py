#!/usr/bin/env python3
"""test_contextual_prefix.py — hermetic tests for scripts/contextual-prefix.py.

Covers the Haiku cache-floor decision (cache_control_for). The network paths
(tier-1 Anthropic API, tier-2 claude CLI) are egress-gated and excluded from
hermetic tests by design; only the pure floor logic is exercised here. No
network, no LLM, no ollama. Pure stdlib.

Usage:
  python3 tests/test_contextual_prefix.py
"""
import importlib.util
import json
import tempfile
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent
HELPER = ROOT / "scripts" / "contextual-prefix.py"

spec = importlib.util.spec_from_file_location("contextual_prefix", HELPER)
cp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cp)


class Fail(SystemExit):
    pass


def assert_eq(label, expected, actual):
    if expected != actual:
        raise Fail(f"FAIL {label}: expected {expected!r}, got {actual!r}")
    print(f"OK   {label}")


def assert_true(label, cond):
    if not cond:
        raise Fail(f"FAIL {label}")
    print(f"OK   {label}")


# ─── Below the floor → no cache_control (silent no-op avoided) ───────────────
def test_below_floor_returns_none():
    body = "x" * (cp.HAIKU_CACHE_MIN_CHARS - 1)
    assert_eq("body 1 char below floor → None", None, cp.cache_control_for(body))


def test_empty_body_returns_none():
    assert_eq("empty body → None", None, cp.cache_control_for(""))


# ─── At / above the floor → ephemeral cache_control ──────────────────────────
def test_at_floor_returns_ephemeral():
    body = "x" * cp.HAIKU_CACHE_MIN_CHARS
    assert_eq("body exactly at floor → ephemeral",
              {"type": "ephemeral"}, cp.cache_control_for(body))


def test_above_floor_returns_ephemeral():
    body = "x" * (cp.HAIKU_CACHE_MIN_CHARS * 3)
    assert_eq("body well above floor → ephemeral",
              {"type": "ephemeral"}, cp.cache_control_for(body))


# ─── Integration: built payload attaches cache_control only above the floor ──
def test_payload_attaches_cache_control_by_body_size():
    """Mock the network. Assert the API payload attaches cache_control to the
    page block only when the body clears the floor, and the multi-line model
    reply is truncated to one line. No network, no LLM."""
    captured = {}

    class _Resp:
        def __init__(self, d):
            self._d = json.dumps(d).encode()

        def read(self):
            return self._d

        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

    def _fake_urlopen(req, timeout=None):
        captured["body"] = json.loads(req.data.decode())
        return _Resp({
            "content": [{"type": "text", "text": "one situating line.\nIGNORED"}],
            "usage": {"cache_creation_input_tokens": 7, "cache_read_input_tokens": 3},
        })

    with mock.patch.object(cp.urllib.request, "urlopen", _fake_urlopen):
        out = cp.anthropic_api_prefix("KEY", "T", "x" * cp.HAIKU_CACHE_MIN_CHARS, "chunk")
        assert_eq("multi-line reply truncated to one line", "one situating line.", out)
        assert_true("above-floor body attaches cache_control",
                    "cache_control" in captured["body"]["system"][1])
        cp.anthropic_api_prefix("KEY", "T", "tiny", "chunk")
        assert_true("below-floor body omits cache_control",
                    "cache_control" not in captured["body"]["system"][1])


def test_chunk_reconciliation_and_deleted_page_gc():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        wiki = root / "wiki"
        chunks = root / ".vault-meta" / "chunks"
        wiki.mkdir()
        page = wiki / "page.md"
        page.write_text("---\naddress: c-000001\ntitle: Page\n---\n\n" + ("a" * 2100) + "\n\n" + ("b" * 2100))
        with mock.patch.object(cp, "VAULT_ROOT", root), \
             mock.patch.object(cp, "WIKI_DIR", wiki), \
             mock.patch.object(cp, "CHUNKS_DIR", chunks):
            cp.process_page(page, force_synthetic=True)
            assert_true("initial page creates multiple chunks",
                        len(list((chunks / "c-000001").glob("chunk-*.json"))) > 1)
            page.write_text("---\naddress: c-000001\ntitle: Page\n---\n\nshort")
            cp.process_page(page, force_synthetic=True)
            assert_eq("shrunk page removes surplus chunks", 1,
                      len(list((chunks / "c-000001").glob("chunk-*.json"))))
            page.write_text("---\naddress: c-000001\ntitle: Page\n---\n")
            cp.process_page(page, force_synthetic=True)
            assert_true("empty page removes former chunk directory",
                        not (chunks / "c-000001").exists())
            orphan = chunks / "c-999999"
            orphan.mkdir()
            (orphan / "chunk-000.json").write_text(json.dumps(
                {"page_path": "wiki/deleted.md"}))
            cp.garbage_collect_deleted_pages(peek=True)
            assert_true("peek preserves deleted-page chunks", orphan.exists())
            cp.garbage_collect_deleted_pages(peek=False)
            assert_true("--all GC removes deleted-page chunks", not orphan.exists())


def main():
    print("=== test_contextual_prefix.py ===")
    test_below_floor_returns_none()
    test_empty_body_returns_none()
    test_at_floor_returns_ephemeral()
    test_above_floor_returns_ephemeral()
    test_payload_attaches_cache_control_by_body_size()
    test_chunk_reconciliation_and_deleted_page_gc()
    print("\nAll contextual-prefix tests passed.")


if __name__ == "__main__":
    main()
