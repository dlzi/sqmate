#!/bin/bash
# SQmate Installation Script

set -euo pipefail

# Default installation paths
PREFIX="${PREFIX:-/usr/local}"
BINDIR="${BINDIR:-$PREFIX/bin}"
DOCDIR="${DOCDIR:-$PREFIX/share/doc/sqmate}"
MANDIR="${MANDIR:-$PREFIX/share/man/man1}"

# Resolve repository layout. Support both source-tree and flat release archives.
if [[ -f src/sqmate.sh ]]; then
    SCRIPT_PATH="src/sqmate.sh"
elif [[ -f sqmate.sh ]]; then
    SCRIPT_PATH="sqmate.sh"
else
    echo "Error: Cannot find sqmate.sh." >&2
    exit 1
fi

if [[ -f docs/man/sqmate.1 ]]; then
    MANPAGE_PATH="docs/man/sqmate.1"
elif [[ -f sqmate.1 ]]; then
    MANPAGE_PATH="sqmate.1"
else
    MANPAGE_PATH=""
fi

# Check permissions against the nearest existing parent, not only PREFIX itself.
check_parent="$PREFIX"
while [[ ! -e "$check_parent" && "$check_parent" != "/" ]]; do
    check_parent="$(dirname "$check_parent")"
done

if [[ ! -w "$check_parent" ]]; then
    echo "Error: Need write permissions to install under $PREFIX. Please run with sudo or choose a writable PREFIX." >&2
    exit 1
fi

# Confirm installation
echo "=== SQmate Installation ==="
echo "This will install SQmate to:"
echo "  Binary:      $BINDIR"
echo "  Docs:        $DOCDIR"
echo "  Man Page:    $MANDIR"
echo ""
read -r -p "Are you sure you want to install SQmate? (y/N): " confirm
[[ $confirm =~ ^[Yy]$ ]] || {
    echo "Installation aborted."
    exit 0
}

# Create directories with error checking
echo "Creating directories..."
for dir in "$BINDIR" "$DOCDIR" "$MANDIR"; do
    mkdir -p "$dir" || {
        echo "Failed to create $dir" >&2
        exit 1
    }
done

# Install the script
echo "Installing the script..."
install -m 755 "$SCRIPT_PATH" "$BINDIR/sqmate" || {
    echo "Failed to install sqmate.sh" >&2
    exit 1
}

# Install documentation
echo "Installing documentation..."
for doc in README.md CHANGELOG.md LICENSE; do
    if [[ -f "$doc" ]]; then
        install -m 644 "$doc" "$DOCDIR/" || {
            echo "Failed to install $doc" >&2
            exit 1
        }
    fi
done

if [[ -n "$MANPAGE_PATH" ]]; then
    if ! install -m 644 "$MANPAGE_PATH" "$MANDIR/sqmate.1"; then
        echo "Failed to install man page" >&2
        exit 1
    fi
fi

echo ""
echo "Installation complete!"
echo "Run 'sqmate help' to get started."
