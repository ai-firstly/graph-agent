.PHONY: all install format lint test test_watch clean build help

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
	gem build graph_agent.gemspec

clean: ## Remove build artifacts
	rm -f *.gem
	rm -rf pkg/ tmp/ coverage/ .rspec_status

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
	@echo 'BUILD'
	@echo '  make build                — build the gem'
	@echo '  make clean                — remove build artifacts'
