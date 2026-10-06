#!/usr/bin/env bash
# Tracker CLI entry point. See .claude/skills/tracker/SKILL.md.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$HOME/.rokit/bin:$PATH"
exec lune run scripts/tracker/main -- "$@"
