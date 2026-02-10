.PHONY: all install format lint test test_watch clean build console tag release help

all: help

######################
# SETUP
######################

install: ## Install dependencies
	bundle install

######################
# TESTING AND COVERAGE
######################

TEST ?= .

test: ## Run the test suite (TEST=path/to/spec.rb to run a specific file)
	bundle exec rspec $(if $(filter-out .,$(TEST)),$(TEST),)

test_watch: ## Run tests in watch mode (requires guard-rspec)
	bundle exec guard

######################
# LINTING AND FORMATTING
######################

format: ## Run code formatters
	bundle exec rubocop -a

lint: ## Run linters
	bundle exec rubocop

######################
# BUILD AND RELEASE
######################

build: ## Build the gem
	bundle exec rake build

clean: ## Remove build artifacts
	rm -f *.gem
	rm -f graph_agent-*.gem
	rm -rf pkg/ tmp/ coverage/ .rspec_status

console: ## Start an interactive console with the gem loaded
	bundle exec irb -r graph_agent

tag: ## Create and push a version tag. Usage: make tag [VERSION=x.y.z]
	@git fetch --tags; \
	if [ -z "$(VERSION)" ]; then \
		LATEST=$$(git tag -l 'v[0-9]*' --sort=-v:refname | head -n1); \
		if [ -z "$$LATEST" ]; then \
			NEW_TAG="v0.0.1"; \
		else \
			MAJOR=$$(echo $$LATEST | sed 's/^v//' | cut -d. -f1); \
			MINOR=$$(echo $$LATEST | sed 's/^v//' | cut -d. -f2); \
			PATCH=$$(echo $$LATEST | sed 's/^v//' | cut -d. -f3); \
			PATCH=$$((PATCH + 1)); \
			NEW_TAG="v$$MAJOR.$$MINOR.$$PATCH"; \
		fi; \
	else \
		NEW_TAG="v$(VERSION)"; \
		LATEST=$$(git tag -l 'v[0-9]*' --sort=-v:refname | head -n1); \
		if [ "$$LATEST" = "$$NEW_TAG" ]; then \
			echo "Tag $$NEW_TAG already exists on remote, deleting and re-pushing..."; \
			git tag -d "$$NEW_TAG" 2>/dev/null || true; \
			git push origin --delete "$$NEW_TAG" 2>/dev/null || true; \
		elif git tag -l "$$NEW_TAG" | grep -q "$$NEW_TAG"; then \
			echo "Error: Tag $$NEW_TAG exists but is not the latest tag (latest: $$LATEST). Aborting."; \
			exit 1; \
		fi; \
	fi; \
	NEW_VERSION=$$(echo $$NEW_TAG | sed 's/^v//'); \
	echo "Updating version to $$NEW_VERSION ..."; \
	sed -i '' "s/VERSION = [\"'].*[\"']/VERSION = '$$NEW_VERSION'/" lib/graph_agent/version.rb; \
	git add lib/graph_agent/version.rb; \
	git commit -m "Release $$NEW_TAG" --allow-empty; \
	git tag "$$NEW_TAG"; \
	echo "Pushing tag $$NEW_TAG ..."; \
	git push origin HEAD; \
	git push origin "$$NEW_TAG"; \
	echo "Done! Tagged and pushed $$NEW_TAG"

release: tag ## Release the gem (tag + push to RubyGems)
	bundle exec rake release_gem

######################
# HELP
######################

help: ## Show this help
	@echo '=========================='
	@echo '  GraphAgent — Makefile'
	@echo '=========================='
	@echo ''
	@echo 'SETUP'
	@echo '  make install              — install dependencies'
	@echo ''
	@echo 'TESTING'
	@echo '  make test                 — run the full test suite'
	@echo '  make test TEST=spec/...   — run a specific test file'
	@echo ''
	@echo 'LINTING & FORMATTING'
	@echo '  make format               — run code formatters'
	@echo '  make lint                 — run linters'
	@echo ''
	@echo 'BUILD & RELEASE'
	@echo '  make build                — build the gem'
	@echo '  make clean                — remove build artifacts'
	@echo '  make console              — start interactive console'
	@echo '  make tag                  — auto-increment patch version, tag & push'
	@echo '  make tag VERSION=x.y.z    — tag a specific version & push'
	@echo '  make release              — tag + release gem to RubyGems'
