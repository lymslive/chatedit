.PHONY: test test-perl test-python test-node install help

# Destination directory for installed scripts (override with: make install INSTALL_DIR=...)
INSTALL_DIR ?= $(HOME)/bin

_INSTALL_PL = $(INSTALL_DIR)/ai-chat.pl
_INSTALL_SH = $(INSTALL_DIR)/ai-curl.sh
_INSTALL_PY = $(INSTALL_DIR)/ai-chat.py
_INSTALL_JS = $(INSTALL_DIR)/ai-chat.js

help:
	@echo "Targets:"
	@echo "  test         Run all unit tests (Perl + Python + Node)"
	@echo "  test-perl    Run Perl unit tests with prove (perl/t/)"
	@echo "  test-python  Run Python unit tests (python/tests/)"
	@echo "  test-node    Run Node.js unit tests (node/test/)"
	@echo "  install      Install ai-chat.pl, ai-curl.sh, ai-chat.py, ai-chat.js to INSTALL_DIR (default: ~/bin)"
	@echo "               Only copies files that are newer than the installed version."
	@echo "  help         Show this help"

test: test-perl test-python test-node

test-perl:
	prove perl/t/

test-python:
	python3 -m unittest discover python/tests/

test-node:
	node --test node/test/*.js

# install: 仅在源文件比目标更新时才复制（利用 Make 依赖机制）
install: $(_INSTALL_PL) $(_INSTALL_SH) $(_INSTALL_PY) $(_INSTALL_JS)

$(INSTALL_DIR):
	mkdir -p $@

$(_INSTALL_PL): perl/ai-chat.pl | $(INSTALL_DIR)
	install -m 755 $< $@
	@echo "Installed $< -> $@"

$(_INSTALL_SH): bash/ai-curl.sh | $(INSTALL_DIR)
	install -m 755 $< $@
	@echo "Installed $< -> $@"

$(_INSTALL_PY): python/ai-chat.py | $(INSTALL_DIR)
	install -m 755 $< $@
	@echo "Installed $< -> $@"

$(_INSTALL_JS): node/ai-chat.js | $(INSTALL_DIR)
	install -m 755 $< $@
	@echo "Installed $< -> $@"
