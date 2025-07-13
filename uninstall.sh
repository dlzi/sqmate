#!/bin/bash
# SQmate Uninstallation Script

set -e

# Default installation paths
PREFIX="${PREFIX:-/usr/local}"
BINDIR="${BINDIR:-$PREFIX/bin}"
DOCDIR="${DOCDIR:-$PREFIX/share/doc/sqmate}"
MANDIR="${MANDIR:-$PREFIX/share/man/man1}"
COMPLETIONDIR="${COMPLETIONDIR:-$PREFIX/share/bash-completion/completions}"
CONFIG_DIR="${HOME}/.config/sqmate"

# Confirm uninstallation
echo "=== SQmate Uninstallation ==="
echo "This will remove SQmate from:"
echo "  Binary:      $BINDIR"
echo "  Docs:        $DOCDIR"
echo "  Man Page:    $MANDIR"
echo "  Completion:  $COMPLETIONDIR"
echo ""
read -r -p "Are you sure you want to uninstall SQmate? (y/N): " confirm
[[ $confirm =~ ^[Yy]$ ]] || {
    echo "Uninstallation aborted."
    exit 0
}

# Remove the script
echo "Removing the script..."
[ -f "$BINDIR/sqmate" ] && rm -f "$BINDIR/sqmate" || echo "Main script not found at $BINDIR/sqmate, skipping."

# Remove documentation
echo "Removing documentation..."
[ -d "$DOCDIR" ] && rm -rf "$DOCDIR" || echo "Documentation directory not found at $DOCDIR, skipping."

# Remove man page
echo "Removing man page..."
[ -f "$MANDIR/sqmate.1" ] && rm -f "$MANDIR/sqmate.1" || echo "Man page not found at $MANDIR/sqmate.1, skipping."

# Remove bash completion
echo "Removing bash completion..."
[ -f "$COMPLETIONDIR/sqmate" ] && rm -f "$COMPLETIONDIR/sqmate" || echo "Bash completion not found at $COMPLETIONDIR/sqmate, skipping."

# Optional cleanup of configuration directory
if [ -d "$CONFIG_DIR" ]; then
    echo ""
    echo "Configuration directory found at $CONFIG_DIR."
    read -r -p "Remove configuration directory and all its contents? (y/N): " config_confirm
    if [[ $config_confirm =~ ^[Yy]$ ]]; then
        echo "Removing configuration directory..."
        rm -rf "$CONFIG_DIR" || {
            echo "Failed to remove configuration directory: $CONFIG_DIR"
            exit 1
        }
        echo "Configuration directory removed."
    else
        echo "Configuration directory left intact."
    fi
fi

echo ""
echo "Uninstallation complete!"
echo "SQmate has been removed from your system."
