.PHONY: build help install run test

help: ## Display this help screen
	@echo
	@echo "Walter - Build Automation"
	@echo
	@echo "Usage:"
	@echo
	@sed -n 's/^\([A-Za-z0-9\-]*\):.*## \(.*\)$$/\t\1: \2/p' Makefile | sort | column -t -s ':'
	@echo

build: ## Build Walter.app - SwiftPM will handle incremental compilation
	./dist/build-release.sh

run: build  ## Run the app from dist/build/Walter.app
	open dist/build/Walter.app

install: build  ## Install Walter to /Applications
	@test ! -e /Applications/Walter.app && test ! -L /Applications/Walter.app || \
		{ echo "Walter.app already exists in /Applications; quit Walter and move it to the Trash first." >&2; exit 1; }
	ditto dist/build/Walter.app /Applications/Walter.app

test:  ## Run unit tests
	bash dist/test.sh
