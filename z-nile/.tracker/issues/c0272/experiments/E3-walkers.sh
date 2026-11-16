#!/usr/bin/env bash
# E3: the specs that walk every lesson file pass with the reference lesson and its note present, in a throwaway
# clone of this worktree (mktemp -d, removed at the end). Writes nothing outside the folder.
# Run: ./zn run --time 900 -- bash E3-walkers.sh
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd -P)"
top="$(git -C "$here" rev-parse --show-toplevel)"
t="$(mktemp -d)"
trap 'rm -rf "$t"' EXIT
# a dispatched step's publish broker pushes to the real origin: the clone must never see it, the step's git
# wrapper, run state or credential (lesson z-design/clone-experiments-drop-the-step-environment)
for v in $(compgen -e | grep '^ZN_'); do unset "$v"; done
unset GH_CONFIG_DIR
PATH=$(tr ':' '\n' <<<"$PATH" | grep -v '/z-nile/bin$' | paste -sd: -)
git clone -q --no-local "$top" "$t/repo"
I=z-nile/.tracker/issues/c0272
rm -rf "$t/repo/$I" && cp -R "$top/$I" "$t/repo/$I"
cp "$top"/z-nile/skills/z-design/lessons/*.md "$t/repo/z-nile/skills/z-design/lessons/"
cd "$t/repo" || exit 1
cp "$I/experiments/ref-lesson.md.txt" z-nile/skills/z-design/lessons/superseding-prep-hands-over-the-claim.md
echo '- note PR #256 was closed with a comment that reached nobody, and the agent holding the claim on c0264 kept designing (the capture of c0272) (erred z-design): z-design/superseding-prep-hands-over-the-claim' >> "$I/harvest.md"
git add -A && git -c user.name=e3 -c user.email=e3@example.invalid commit -qm "e3: the lesson in place"
cd z-nile || exit 1
lune run tests/run -- tests/acceptance/c0111/lesson-format.spec.luau tests/acceptance/c0111/harvest.spec.luau \
  tests/acceptance/c0111/skill-docs.spec.luau tests/acceptance/c0115/lessons.spec.luau \
  tests/acceptance/c0119/scope-lessons.spec.luau tests/tooling/lessons-hidden.spec.luau 2>&1 | tail -6
