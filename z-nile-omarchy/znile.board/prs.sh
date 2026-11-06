#!/usr/bin/env bash
# Prints the repo's open pull requests as JSON for the znile board:
# [{number, title, headRefName, isDraft, url}]. Needs gh, signed in.
# Prints [] (and exits 0) when gh can't answer, so the board still loads.
set -uo pipefail
cd "${1:?usage: prs.sh <repo>}" || exit 2
out=$(timeout 20 gh pr list --state open --limit 100 \
  --json number,title,headRefName,isDraft,url 2>/dev/null) || out="[]"
printf '%s\n' "${out:-[]}"
