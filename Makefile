NVIM ?= nvim
STYLUA ?= stylua

.PHONY: test lint format

test:
	$(NVIM) --headless --clean -l tests/run.lua

lint:
	$(STYLUA) --check lua tests

format:
	$(STYLUA) lua tests
