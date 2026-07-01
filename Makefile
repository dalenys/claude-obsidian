# claude-obsidian Makefile
# Test runner entry points for DragonScale and vault tooling.

.PHONY: test test-address test-tiling test-boundary test-bm25 test-retrieve \
        test-lock test-concurrent test-mode test-contextual test-install-transport \
        test-version-sync test-secrets lint check-secrets setup-dragonscale \
        setup-retrieve setup-mode clean-test-state help

help:
	@echo "claude-obsidian developer targets:"
	@echo "  make test              Run all v1.7 tests (DragonScale + retrieval + concurrency)"
	@echo "  make test-address     scripts/allocate-address.sh tests (shell)"
	@echo "  make test-tiling      scripts/tiling-check.py tests (python, no ollama required)"
	@echo "  make test-boundary    scripts/boundary-score.py tests (python, no prereqs)"
	@echo "  make test-bm25        scripts/bm25-index.py tests (python, hermetic)"
	@echo "  make test-retrieve    scripts/retrieve.py + rerank.py tests (python, hermetic)"
	@echo "  make test-lock        scripts/wiki-lock.sh tests (shell, hermetic)"
	@echo "  make test-concurrent  multi-writer correctness gate (shell, hermetic)"
	@echo "  make test-mode        scripts/wiki-mode.py tests (python, hermetic)"
	@echo "  make test-contextual  scripts/contextual-prefix.py cache-floor tests (python, hermetic)"
	@echo "  make test-version-sync Assert version agrees across plugin.json/marketplace.json/CHANGELOG"
	@echo "  make test-secrets     tests/test_check_no_secrets.sh (shell, hermetic)"
	@echo "  make lint             Run shellcheck + ruff (skipped if not installed)"
	@echo "  make check-secrets    Scan tracked files for secrets/host paths (no third-party tools)"
	@echo "  make setup-dragonscale Run bin/setup-dragonscale.sh against this vault"
	@echo "  make setup-retrieve   Run bin/setup-retrieve.sh against this vault (opt-in v1.7)"
	@echo "  make setup-mode       Run bin/setup-mode.sh to pick a methodology mode (opt-in v1.8)"
	@echo "  make clean-test-state Remove runtime lockfiles and tiling/embed caches"

test: test-address test-tiling test-boundary test-bm25 test-retrieve test-lock test-concurrent test-mode test-contextual test-install-transport test-version-sync test-secrets
	@echo ""
	@echo "All tests passed."

test-address:
	@echo "=== test_allocate_address.sh ==="
	@bash tests/test_allocate_address.sh

test-tiling:
	@echo "=== test_tiling_check.py ==="
	@python3 tests/test_tiling_check.py

test-boundary:
	@echo "=== test_boundary_score.py ==="
	@python3 tests/test_boundary_score.py

test-bm25:
	@echo "=== test_bm25_index.py ==="
	@python3 tests/test_bm25_index.py

test-retrieve:
	@echo "=== test_retrieve.py ==="
	@python3 tests/test_retrieve.py

test-lock:
	@echo "=== test_wiki_lock.sh ==="
	@bash tests/test_wiki_lock.sh

test-concurrent:
	@echo "=== test_concurrent_write.sh ==="
	@bash tests/test_concurrent_write.sh

test-mode:
	@echo "=== test_wiki_mode.py ==="
	@python3 tests/test_wiki_mode.py

test-contextual:
	@echo "=== test_contextual_prefix.py ==="
	@python3 tests/test_contextual_prefix.py

test-install-transport:
	@echo "=== test_install_transport.sh ==="
	@bash tests/test_install_transport.sh

test-version-sync:
	@echo "=== test_check_version_sync.py ==="
	@python3 tests/test_check_version_sync.py
	@echo "=== check-version-sync.py (live repo) ==="
	@python3 scripts/check-version-sync.py

test-secrets:
	@echo "=== test_check_no_secrets.sh ==="
	@bash tests/test_check_no_secrets.sh

# Opt-in static analysis. Both tools are dev-only (not runtime deps); the target
# skips gracefully when a tool is absent so `make test` never depends on them.
# Runs both linters even if the first fails, then reports a single exit status.
lint:
	@echo "=== lint: shellcheck + ruff ==="
	@rc=0; \
	if command -v shellcheck >/dev/null 2>&1; then \
	  shellcheck scripts/*.sh bin/*.sh tests/*.sh && echo "shellcheck: OK" || rc=1; \
	else echo "shellcheck: not installed — skipping (brew install shellcheck)"; fi; \
	if command -v ruff >/dev/null 2>&1; then \
	  ruff check scripts tests && echo "ruff: OK" || rc=1; \
	else echo "ruff: not installed — skipping (pipx install ruff)"; fi; \
	exit $$rc

check-secrets:
	@bash scripts/check-no-secrets.sh

setup-dragonscale:
	@bash bin/setup-dragonscale.sh

setup-retrieve:
	@bash bin/setup-retrieve.sh

setup-mode:
	@bash bin/setup-mode.sh

clean-test-state:
	@rm -f .vault-meta/.address.lock .vault-meta/.tiling.lock .vault-meta/.bm25.lock \
	      .vault-meta/.embed-cache.lock .vault-meta/.wiki-lock.meta \
	      .vault-meta/tiling-cache.json \
	      .vault-meta/tiling-cache.*.tmp .vault-meta/embed-cache.json \
	      .vault-meta/embed-cache.*.tmp .vault-meta/transport.json \
	      .vault-meta/transport.*.tmp
	@rm -rf .vault-meta/chunks/ .vault-meta/bm25/ .vault-meta/locks/
	@rm -f .vault-meta/mode.json .vault-meta/mode.*.tmp .vault-meta/hook.log
	@echo "Runtime lockfiles, caches, and v1.7/v1.8 runtime artifacts removed."
