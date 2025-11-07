# Git Hooks Setup

This directory contains Git hooks that are version controlled and can be shared with the team.

## Installation

To install the Git hooks, run:

```bash
./scripts/install-hooks.sh
```

Or from the project root:

```bash
bash scripts/install-hooks.sh
```

This will copy the hooks from `scripts/hooks/` to `.git/hooks/` and make them executable.

## Available Hooks

- **pre-commit**: Automatically formats all Dart code with `dart format` before each commit and stages the formatted files.
- **pre-push**: Verifies that all Dart code is properly formatted before allowing a push.

## Why Hooks Are Not Tracked by Git

Git hooks in `.git/hooks/` are not tracked by Git by default. This is why we store them in `scripts/hooks/` and provide an installation script. This allows:

1. Hooks to be version controlled
2. Team members to easily install the same hooks
3. Hooks to be updated and shared via Git

