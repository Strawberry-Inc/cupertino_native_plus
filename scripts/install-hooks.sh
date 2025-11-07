#!/bin/bash

# Script to install Git hooks from scripts/hooks to .git/hooks
# This allows hooks to be version controlled and shared with the team

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HOOKS_SOURCE="$SCRIPT_DIR/hooks"
HOOKS_TARGET="$PROJECT_ROOT/.git/hooks"

echo "Installing Git hooks..."

# Create .git/hooks directory if it doesn't exist
mkdir -p "$HOOKS_TARGET"

# Copy all hooks from scripts/hooks to .git/hooks
for hook in "$HOOKS_SOURCE"/*; do
    if [ -f "$hook" ]; then
        hook_name=$(basename "$hook")
        target_hook="$HOOKS_TARGET/$hook_name"
        
        echo "Installing $hook_name..."
        cp "$hook" "$target_hook"
        chmod +x "$target_hook"
    fi
done

echo "✓ Git hooks installed successfully!"
echo ""
echo "Installed hooks:"
ls -la "$HOOKS_TARGET"/* 2>/dev/null | grep -E "pre-commit|pre-push" || echo "No hooks found"

