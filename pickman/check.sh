#!/usr/bin/env bash
# pickman's gate (c0120): the repository's gate for this project alone. See .claude/skills/testing/SKILL.md.
#   pickman/check.sh [--full|--affected] [--base REF]
exec bash "$(dirname "$0")/../z-nile/check.sh" --project pickman "$@"
