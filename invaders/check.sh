#!/usr/bin/env bash
# invaders's gate (c0184): the repository's gate for this project alone. See z-nile/skills/zz-test/SKILL.md.
#   invaders/check.sh [--full|--affected] [--base REF]
exec bash "$(dirname "$0")/../z-nile/check.sh" --project invaders "$@"
