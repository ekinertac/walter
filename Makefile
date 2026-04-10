# Makefile — Walter launcher (Swift + AppKit)
#
#   make             → build + run (default)
#   make build       → debug build
#   make release     → optimised release build
#   make run         → build and launch
#   make dist        → build + sign + notarize + DMG
#   make dist-quick  → build + sign + DMG (skip notarization)
#   make clean       → remove build artefacts
#   make install     → copy release binary to ~/.local/bin

BINARY     := Walter
SWIFT      := swift
BUILD_DIR  := Walter
PREFIX     ?= $(HOME)/.local/bin
CONFIG_DIR ?= $(HOME)/.config/walter

.DEFAULT_GOAL := run

# ---------------------------------------------------------------------------
# Dev
# ---------------------------------------------------------------------------

.PHONY: build
build:
	cd $(BUILD_DIR) && $(SWIFT) build

.PHONY: run
run: build
	cd $(BUILD_DIR) && $(SWIFT) run

.PHONY: release
release:
	cd $(BUILD_DIR) && $(SWIFT) build -c release

# ---------------------------------------------------------------------------
# Distribution (sign + notarize + DMG)
# ---------------------------------------------------------------------------

.PHONY: dist
dist:
	./dist/build-release.sh

.PHONY: dist-quick
dist-quick:
	./dist/build-release.sh --skip-notarize

# ---------------------------------------------------------------------------
# Config bootstrap
# ---------------------------------------------------------------------------

.PHONY: init-config
init-config:
	@mkdir -p $(CONFIG_DIR)
	@for f in config-example/*; do \
		dest=$(CONFIG_DIR)/$$(basename $$f); \
		if [ -e "$$dest" ]; then \
			echo "skip  $$dest (already exists)"; \
		else \
			cp $$f $$dest; \
			echo "wrote $$dest"; \
		fi \
	done

# ---------------------------------------------------------------------------
# Install
# ---------------------------------------------------------------------------

.PHONY: install
install: release
	@mkdir -p $(PREFIX)
	cp $(BUILD_DIR)/.build/release/$(BINARY) $(PREFIX)/$(BINARY)
	@echo "Installed to $(PREFIX)/$(BINARY)"
	@$(MAKE) init-config

.PHONY: uninstall
uninstall:
	rm -f $(PREFIX)/$(BINARY)
	@echo "Removed $(PREFIX)/$(BINARY)"

# ---------------------------------------------------------------------------
# Housekeeping
# ---------------------------------------------------------------------------

.PHONY: clean
clean:
	cd $(BUILD_DIR) && $(SWIFT) package clean
	rm -rf dist/build

.PHONY: help
help:
	@echo "Walter — available make targets:"
	@echo ""
	@echo "  build         Debug build"
	@echo "  run           Debug build + launch (default)"
	@echo "  release       Optimised release build"
	@echo "  dist          Build + sign + notarize + DMG (full release)"
	@echo "  dist-quick    Build + sign + DMG (skip notarization, for testing)"
	@echo "  init-config   Copy example config to ~/.config/walter/"
	@echo "  install       Release build + install to PREFIX ($(PREFIX))"
	@echo "  uninstall     Remove installed binary"
	@echo "  clean         Remove build artefacts"
