#!/usr/bin/env bash
# E1: writes the prototype of c0294 into a scratch worktree (argument 1): the prep's item folder, the lesson from a
# reference text (argument 2, default ref-lesson.md.txt) and the harvest note, as the Implementation steps say, and the
# lessons prep itself adds.
set -euo pipefail
P=${1:?prototype worktree}
REF=${2:-ref-lesson.md.txt}
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
[[ $P == */.worktree/proto-c0294 ]] || { echo "refusing: $P is not a proto-c0294 worktree" >&2; exit 1; }
rm -rf "$P/z-nile/.tracker/issues/c0294"
cp -R "$HERE" "$P/z-nile/.tracker/issues/c0294"
cp "$HERE/experiments/$REF" "$P/z-nile/skills/z-ticket/lessons/moved-part-rewrites-the-owner.md"
cat "$HERE/experiments/ref-note.txt" >>"$P/z-nile/.tracker/issues/c0294/harvest.md"
# the lessons prep itself adds (its design-review harvest names them), as the prep commit lands them
ROOT="$(cd "$HERE/../../../.." && pwd -P)"
for l in z-nile/skills/z-design/lessons/lesson-facts-come-from-the-record.md; do cp "$ROOT/$l" "$P/$l"; done
