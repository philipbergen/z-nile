#!/usr/bin/env bash
# E5 (c0277): a shell whose working directory is renamed. Run from the main checkout as
#   ./zn run --time 120 -- bash z-nile/.tracker/issues/c0277/experiments/e5-rename.sh
# (it ran with --time 60 on 2026-11-12). It makes a throwaway worktree from proto-c0277 under a name of its own, plants a
# discard marker, renames the worktree's folder from inside it, and shows that the old path is gone while the relative ./zn
# still runs the renamed worktree's engine and is refused. It refuses to start when its worktree name exists, and removes
# only the worktree it made (no --force: it holds nothing but the marker, an ignored file).
set -u
N="probe-c0277-$$"
[[ ! -e ".worktree/$N" ]] || { echo "refusing: .worktree/$N exists" >&2; exit 1; }
P="$(./zn worktree "$N" --from proto-c0277 2>/dev/null | tail -1)"
[[ -d $P ]] || { echo "no worktree made" >&2; exit 1; }
mkdir -p "$P/.cache"
printf 'discarded worktree: %s-gone\ncopy: x\nbranch: \nbase: \npushed: \nitems: c0001\nsince: 1\n\nthis worktree was discarded: c0001%ss claim was taken over. Clear your context and pick up something new.\n' "$P" "'" >"$P/.cache/discarded"
(
  cd "$P" || exit 1
  git worktree move "$P" "$P-gone"
  echo "pwd -P after the move: $(pwd -P)"
  ls "$P" 2>&1 | head -1
  ./zn lessons --tags 2>&1 | head -2
)
git worktree remove "$P-gone" 2>&1 | head -2
git branch -D "$N" >/dev/null 2>&1 || true
