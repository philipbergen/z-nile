#!/usr/bin/env bash
# c0359 E1: do the format and lint stages still fail a bad file when the tree they read sits under a `.cache` folder
# (the dispatcher's judgement exports the merged tree under .cache/dispatch/judge-*/, and selene.toml excludes
# "**/.cache/**")? Run from the checkout's top:
#   ./zn run --time 60 -- bash z-nile/.tracker/issues/c0359/experiments/E1-lint-under-cache.sh
# Writes only under its own mktemp folders (one under $TMPDIR, one under this checkout's .cache), removed at exit.
set -uo pipefail
export PATH="$HOME/.rokit/bin:$PATH"
top=$(pwd -P)
mkdir -p "$top/.cache"
inside=$(mktemp -d "$top/.cache/c0359-e1.XXXXXX")
outside=$(mktemp -d "${TMPDIR:-/tmp}/c0359-e1.XXXXXX")
trap 'rm -rf "$inside" "$outside"' EXIT
for d in "$inside" "$outside"; do
  mkdir -p "$d/z-nile/.tracker/issues/c9999/acceptance"
  cp "$top/selene.toml" "$top/stylua.toml" "$d/"
  # a shadowing warning only (selene.toml sets shadowing = "warn")
  printf 'local a = 1\nlocal function f()\n\tlocal a = 2\n\treturn a\nend\nreturn { a, f }\n' >"$d/z-nile/w.luau"
  # unformatted for stylua (spacing in a table)
  printf 'local x = {1,2}\nreturn x\n' >"$d/z-nile/.tracker/issues/c9999/acceptance/s.spec.luau"
  (
    cd "$d" || exit 1
    selene --quiet z-nile z-nile/.tracker >/dev/null 2>&1
    se=$?
    stylua --check z-nile z-nile/.tracker >/dev/null 2>&1
    st=$?
    where=outside; [[ $d == "$inside" ]] && where="under .cache"
    echo "$where: selene exit $se, stylua exit $st"
  )
done
