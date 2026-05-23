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
	@install -d $(DESTDIR)$(BINDIR)
	@install -d $(DESTDIR)$(DOCDIR)
	@install -d $(DESTDIR)$(MANDIR)
	
	# Install the script
	@install -m 755 src/sqmate.sh $(DESTDIR)$(BINDIR)/sqmate
	
	# Install documentation
	@install -m 644 README.md $(DESTDIR)$(DOCDIR)/
	@install -m 644 CHANGELOG.md $(DESTDIR)$(DOCDIR)/
	@install -m 644 LICENSE $(DESTDIR)$(DOCDIR)/
	@install -m 644 docs/man/sqmate.1 $(DESTDIR)$(MANDIR)/
	
	@echo "Installation complete!"

uninstall:
	@echo "Uninstalling sqmate..."
	@rm -f $(DESTDIR)$(BINDIR)/sqmate
	@rm -f $(DESTDIR)$(MANDIR)/sqmate.1
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

.PHONY: all install uninstall clean pkgclean distclean