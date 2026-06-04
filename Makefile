# sqmate Makefile
# Default installation paths
PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
DOCDIR ?= $(PREFIX)/share/doc/sqmate
MANDIR ?= $(PREFIX)/share/man/man1

# No build step needed for Bash scripts
all:
	@echo "Nothing to build. Use 'make install' to install sqmate."

install:
	@echo "Installing sqmate..."
	@install -d "$(DESTDIR)$(BINDIR)"
	@install -d "$(DESTDIR)$(DOCDIR)"
	@install -d "$(DESTDIR)$(MANDIR)"
	@if [ -f src/sqmate.sh ]; then script=src/sqmate.sh; elif [ -f sqmate.sh ]; then script=sqmate.sh; else echo "Cannot find sqmate.sh" >&2; exit 1; fi; \
		install -m 755 "$$script" "$(DESTDIR)$(BINDIR)/sqmate"
	@for doc in README.md CHANGELOG.md LICENSE; do \
		if [ -f "$$doc" ]; then install -m 644 "$$doc" "$(DESTDIR)$(DOCDIR)/"; fi; \
	done
	@if [ -f docs/man/sqmate.1 ]; then manpage=docs/man/sqmate.1; elif [ -f sqmate.1 ]; then manpage=sqmate.1; else manpage=; fi; \
		if [ -n "$$manpage" ]; then install -m 644 "$$manpage" "$(DESTDIR)$(MANDIR)/sqmate.1"; fi
	@echo "Installation complete!"

uninstall:
	@echo "Uninstalling sqmate..."
	@rm -f "$(DESTDIR)$(BINDIR)/sqmate"
	@rm -f "$(DESTDIR)$(MANDIR)/sqmate.1"
	@rm -rf "$(DESTDIR)$(DOCDIR)"
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

.PHONY: all install uninstall clean pkgclean distclean
