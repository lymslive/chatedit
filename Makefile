.PHONY: test install help

# Destination directory for installed scripts (override with: make install INSTALL_DIR=...)
INSTALL_DIR ?= $(HOME)/bin

help:
	@echo "Targets:"
	@echo "  test     Run unit tests with prove (perl/t/)"
	@echo "  install  Copy ai-chat.pl and ai-curl.sh to INSTALL_DIR (default: ~/bin)"
	@echo "  help     Show this help"

test:
	prove perl/t/

install:
	@mkdir -p $(INSTALL_DIR)
	install -m 755 perl/ai-chat.pl  $(INSTALL_DIR)/ai-chat.pl
	install -m 755 bash/ai-curl.sh  $(INSTALL_DIR)/ai-curl.sh
	@echo "Installed to $(INSTALL_DIR)"
