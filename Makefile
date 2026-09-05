# Makefile — Walter launcher (Swift + AppKit)
#
#   make             → build + run (default)
#   make build       → debug build
#   make release     → optimised release build
#   make run         → build and launch
#   make dist        → build + sign + notarize + DMG
#   make dist-quick  → build + sign + DMG (skip notarization)
#   make reinstall   → quit running Walter, remove /Applications/Walter.app, install latest build
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

.PHONY: test
test:
	cd $(BUILD_DIR) && $(SWIFT) test

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
# Reinstall (quit → uninstall → build → install to /Applications)
# ---------------------------------------------------------------------------

APP_BUNDLE := /Applications/Walter.app
BUILT_APP  := dist/build/Walter.app

.PHONY: reinstall
reinstall:
	@# Fast dev install: build a signed .app and copy it to /Applications.
	@# Skips notarization AND the DMG packaging that `make dist` runs — the
	@# DMG isn't used here anyway (we just cp Walter.app out of the DMG
	@# staging dir), so building it wastes ~15s per iteration on
	@# create-dmg's disk-image mount and window-arrangement AppleScript.
	@# Codesigning still runs so Accessibility permissions granted to the
	@# /Applications binary persist across rebuilds.
	@#
	@# The `open` at the end WILL race with a still-exiting process: if
	@# Walter is technically still running when `open` fires, macOS just
	@# brings the old process to the front instead of launching the new
	@# binary. Poll until the process is really gone before continuing.
	@echo "→ Quitting Walter..."
	@osascript -e 'tell application "Walter" to quit' 2>/dev/null || true
	@sleep 1
	@pkill -x Walter 2>/dev/null || true
	@while pgrep -x Walter >/dev/null 2>&1; do sleep 0.1; done
	@echo "→ Removing $(APP_BUNDLE)..."
	@rm -rf $(APP_BUNDLE)
	@echo "→ Building signed .app (no DMG)..."
	@./dist/build-release.sh --skip-notarize --skip-dmg
	@echo "→ Installing to /Applications..."
	@cp -R $(BUILT_APP) /Applications/
	@echo "→ Launching Walter..."
	@open /Applications/Walter.app
	@echo "Done — Walter reinstalled and running."

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
	@echo "  reinstall     Quit Walter, remove /Applications/Walter.app, build + reinstall"
	@echo "  init-config   Copy example config to ~/.config/walter/"
	@echo "  install       Release build + install to PREFIX ($(PREFIX))"
	@echo "  uninstall     Remove installed binary"
	@echo "  clean         Remove build artefacts"
