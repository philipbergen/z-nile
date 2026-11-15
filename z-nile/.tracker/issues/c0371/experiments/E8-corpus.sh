#!/usr/bin/env bash
# E8: run from z-nile/ as `../zn run --time 280 -- bash .tracker/issues/c0371/experiments/E8-corpus.sh` once
# z-nile/tests/acceptance/c0120/checkpaths.luau exists (the prototype's, or the executor's). It builds main's reader from
# origin/main's c0120 check-paths spec (the scanner part, up to `present`) and compares the two over every check.sh.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)/z-nile"
mkdir -p .cache
{
  echo '--!strict'
  echo 'local serde = require("@lune/serde")'
  git show origin/main:z-nile/tests/acceptance/c0120/check-paths.spec.luau | awk '/^local PREFIXES/{p=1} /^-- does `path`/{p=0} p'
  echo 'return { literals = literals }'
} > .cache/e8-old.luau
cp .tracker/issues/c0371/experiments/E8-corpus.luau.txt .cache/e8.luau
lune run .cache/e8
