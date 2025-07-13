# SQMATE Makefile
# Universal SQL Server Manager for MySQL and MariaDB portable installations

# Default installation paths
PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
DOCDIR ?= $(PREFIX)/share/doc/sqmate
MANDIR ?= $(PREFIX)/share/man/man1
COMPLETIONDIR ?= $(PREFIX)/share/bash-completion/completions

# Project info
PROJECT_NAME = sqmate
VERSION = 1.0.0
MAIN_SCRIPT = src/sqmate.sh

# No build step needed for Bash scripts
all:
	@echo "Nothing to build. Use 'make install' to install SQMATE."

install:
	@echo "Installing SQMATE..."
	@install -d $(DESTDIR)$(BINDIR)
	@install -d $(DESTDIR)$(DOCDIR)
	@install -d $(DESTDIR)$(MANDIR)
	@install -d $(DESTDIR)$(COMPLETIONDIR)
	
	# Install the main script
	@install -m 755 $(MAIN_SCRIPT) $(DESTDIR)$(BINDIR)/$(PROJECT_NAME)
	
	# Install documentation
	@install -m 644 README.md $(DESTDIR)$(DOCDIR)/
	@install -m 644 CHANGELOG.md $(DESTDIR)$(DOCDIR)/
	@install -m 644 LICENSE $(DESTDIR)$(DOCDIR)/
	@install -m 644 CONTRIBUTING.md $(DESTDIR)$(DOCDIR)/
	@install -m 644 docs/man/sqmate.1 $(DESTDIR)$(MANDIR)/
	
	# Install bash completion
	@install -m 644 completion/bash/sqmate $(DESTDIR)$(COMPLETIONDIR)/
	
	@echo "Installation complete!"
	@echo "Run 'sqmate help' to get started."

uninstall:
	@echo "Uninstalling SQMATE..."
	@rm -f $(DESTDIR)$(BINDIR)/$(PROJECT_NAME)
	@rm -f $(DESTDIR)$(MANDIR)/sqmate.1
	@rm -f $(DESTDIR)$(COMPLETIONDIR)/sqmate
	@rm -rf $(DESTDIR)$(DOCDIR)
	@echo "Uninstall complete!"

clean:
	@echo "Cleaning up build artifacts..."
	@rm -f *~
	@rm -f *.bak
	@rm -f *.log
	@rm -f *.tar.gz
	@rm -rf dist
	@rm -rf build
	@rm -rf __pycache__
	@echo "Clean complete!"

# For makepkg/pacman package building cleanup
pkgclean:
	@echo "Cleaning up package build artifacts..."
	@rm -rf src/sqmate-*
	@rm -rf pkg
	@rm -f *.pkg.tar.zst
	@rm -f *.pkg.tar.xz
	@echo "Package clean complete!"

distclean: clean pkgclean
	@echo "Performing deep clean..."
	@rm -rf .venv
	@rm -rf .cache
	@echo "Deep clean complete!"

# Development targets
check:
	@echo "Running syntax checks..."
	@bash -n $(MAIN_SCRIPT)
	@echo "Syntax check passed!"

test: check
	@echo "Running basic tests..."
	@$(MAIN_SCRIPT) version > /dev/null
	@echo "Basic tests passed!"

# Create distribution archive
dist:
	@echo "Creating distribution archive..."
	@mkdir -p dist
	@tar -czf dist/$(PROJECT_NAME)-$(VERSION).tar.gz \
		--transform 's,^,$(PROJECT_NAME)-$(VERSION)/,' \
		$(MAIN_SCRIPT) \
		README.md \
		CHANGELOG.md \
		LICENSE \
		CONTRIBUTING.md \
		Makefile \
		PKGBUILD \
		docs/ \
		completion/ \
		install.sh \
		uninstall.sh
	@echo "Distribution archive created: dist/$(PROJECT_NAME)-$(VERSION).tar.gz"

# Install locally for development/testing
install-local:
	@echo "Installing SQMATE locally to ~/.local/bin..."
	@mkdir -p ~/.local/bin
	@mkdir -p ~/.local/share/man/man1
	@mkdir -p ~/.local/share/bash-completion/completions
	@install -m 755 $(MAIN_SCRIPT) ~/.local/bin/$(PROJECT_NAME)
	@install -m 644 docs/man/sqmate.1 ~/.local/share/man/man1/
	@install -m 644 completion/bash/sqmate ~/.local/share/bash-completion/completions/
	@echo "Local installation complete!"
	@echo "Add ~/.local/bin to your PATH if not already present."

# Remove local installation
uninstall-local:
	@echo "Removing local SQMATE installation..."
	@rm -f ~/.local/bin/$(PROJECT_NAME)
	@rm -f ~/.local/share/man/man1/sqmate.1
	@rm -f ~/.local/share/bash-completion/completions/sqmate
	@echo "Local uninstall complete!"

# Show installation paths
show-paths:
	@echo "Installation paths:"
	@echo "  PREFIX:        $(PREFIX)"
	@echo "  BINDIR:        $(BINDIR)"
	@echo "  DOCDIR:        $(DOCDIR)"
	@echo "  MANDIR:        $(MANDIR)"
	@echo "  COMPLETIONDIR: $(COMPLETIONDIR)"

# Show project information
info:
	@echo "SQMATE - Universal SQL Server Manager"
	@echo "Version: $(VERSION)"
	@echo "Main script: $(MAIN_SCRIPT)"
	@echo "Project files:"
	@echo "  Script:        $(MAIN_SCRIPT)"
	@echo "  Documentation: README.md CHANGELOG.md LICENSE CONTRIBUTING.md"
	@echo "  Man page:      docs/man/sqmate.1"
	@echo "  Completion:    completion/bash/sqmate"

# Help target
help:
	@echo "SQMATE Makefile - Available targets:"
	@echo ""
	@echo "  all            Default target (does nothing - no build required)"
	@echo "  install        Install SQMATE system-wide (requires root/sudo)"
	@echo "  uninstall      Remove system-wide installation"
	@echo "  install-local  Install to ~/.local/bin (no root required)"
	@echo "  uninstall-local Remove local installation"
	@echo ""
	@echo "  check          Run syntax validation on the main script"
	@echo "  test           Run basic functionality tests"
	@echo "  dist           Create distribution archive"
	@echo ""
	@echo "  clean          Remove temporary files"
	@echo "  pkgclean       Clean package build artifacts"
	@echo "  distclean      Deep clean (clean + pkgclean + dev files)"
	@echo ""
	@echo "  show-paths     Display installation paths"
	@echo "  info           Show project information"
	@echo "  help           Show this help message"
	@echo ""
	@echo "Environment variables:"
	@echo "  PREFIX         Installation prefix (default: /usr/local)"
	@echo "  DESTDIR        Staging directory for package builds"

.PHONY: all install uninstall clean pkgclean distclean check test dist install-local uninstall-local show-paths info help