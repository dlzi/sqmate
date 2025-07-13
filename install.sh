#!/bin/bash
# SQmate Installation Script

set -e

# Default installation paths
PREFIX="${PREFIX:-/usr/local}"
BINDIR="${BINDIR:-$PREFIX/bin}"
DOCDIR="${DOCDIR:-$PREFIX/share/doc/sqmate}"
MANDIR="${MANDIR:-$PREFIX/share/man/man1}"
COMPLETIONDIR="${COMPLETIONDIR:-$PREFIX/share/bash-completion/completions}"

# Check for root permissions
if [ ! -w "$PREFIX" ]; then
    echo "Error: Need root permissions to install to $PREFIX. Please run with sudo."
    exit 1
fi

# Confirm installation
echo "=== SQmate Installation ==="
echo "This will install SQmate to:"
echo "  Binary:      $BINDIR"
echo "  Docs:        $DOCDIR"
echo "  Man Page:    $MANDIR"
echo "  Completion:  $COMPLETIONDIR"
echo ""
read -r -p "Are you sure you want to install SQmate? (y/N): " confirm
[[ $confirm =~ ^[Yy]$ ]] || {
    echo "Installation aborted."
    exit 0
}

# Create directories with error checking
echo "Creating directories..."
for dir in "$BINDIR" "$DOCDIR" "$MANDIR" "$COMPLETIONDIR"; do
    mkdir -p "$dir" || {
        echo "Failed to create $dir"
        exit 1
    }
done

# Install the script
echo "Installing the script..."
install -m 755 src/sqmate.sh "$BINDIR/sqmate" || {
    echo "Failed to install sqmate.sh"
    exit 1
}

# Install documentation
echo "Installing documentation..."
for doc in README.md CHANGELOG.md LICENSE; do
    if [ -f "$doc" ]; then
        install -m 644 "$doc" "$DOCDIR/" || {
            echo "Failed to install $doc"
            exit 1
        }
    fi
done
if [ -f docs/man/sqmate.1 ]; then
    if ! install -m 644 docs/man/sqmate.1 "$MANDIR/"; then
        echo "Failed to install man page"
        exit 1
    fi
fi

# Install bash completion
echo "Installing bash completion..."
if [ -f completion/bash/sqmate ]; then
    install -m 644 completion/bash/sqmate "$COMPLETIONDIR/" || {
        echo "Failed to install bash completion"
        exit 1
    }
fi

echo ""
echo "Installation complete!"
echo "Run 'sqmate help' to get started."
