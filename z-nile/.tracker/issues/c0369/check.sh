#!/usr/bin/env bash
# Acceptance checks for c0369. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0369 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0369"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.

check "AC1: the place is the prep worktree or the one the command runs in when it holds a design of its own with no matching approval, else origin/main, never main's older design behind a pushed prep, and the retry's is the unpublished record" \
  lune run tests/run -- "$A/place.spec.luau"
check "AC2: a merged design is recorded and published by one approve from the main checkout or any worktree, the refusals come first, and a failed publish keeps the record for the retry" \
  lune run tests/run -- "$A/approve-main.spec.luau"
check "AC3: an unmerged design is recorded in its prep worktree and its branch pushed, never forced; other worktrees only from inside, no new branch on origin, nothing pushed on a layer branch" \
  lune run tests/run -- "$A/approve-branch.spec.luau"
check "AC4: the skills and the tooling's refusals state the one command from anywhere" \
  lune run tests/run -- "$A/docs.spec.luau"
check "AC5: the approve tooling specs walk the one command through one answering helper and carry the explainer page, the specs that read approve stay green, and the real tree audits and lessons-checks clean" \
  bash -c '"$ZN_ROOT/zn" audit && "$ZN_ROOT/zn" lessons --check && lune run tests/run -- "$1/docs.spec.luau" tests/tooling/approve.spec.luau tests/tooling/approve-publish.spec.luau tests/tooling/readycheck.spec.luau tests/tooling/work.spec.luau' _ "$A"
check "AC6: c0250, c0267, f0339 and c0394 depend on c0369, none of their documents, check.sh files or acceptance specs keeps the two-command approve, and c0250's and c0394's approve fixtures carry the explainer page and the typed answer" \
  bash -c 'for id in c0250 c0267 f0339 c0394; do d=$("$ZN_ROOT/zn" find "$id") || exit 1; grep -Eq "^depends_on: \[(.*, )?c0369(, .*)?\]$" "$d/$id.md" || { echo "$id does not depend on c0369" >&2; exit 1; }; if grep -rnF -e "then \`./zn approve <id> --publish\`" -e "./zn approve c0001 --publish" -e "./zn approve {u.id} --publish" -e "&& ./zn approve <id> --publish" -e "\"approve\", \"c0250\", \"--publish\"" -e "{ID} --publish\`)" -e "{SECOND} --publish\`)" -e "local dir = \`{f.base}/approve-{id}\`" "$d/$id.md" "$d/check.sh" "$d/acceptance"; then echo "$id still pins the two-command approve" >&2; exit 1; fi; done; for id in c0250 c0394; do d=$("$ZN_ROOT/zn" find "$id") || exit 1; for needle in "explainer.html" "<meta name=\"zn-contract\" content=\"" "\"open\", \"xdg-open\"" "yes y | script -q /dev/null sh -c"; do grep -rqF -e "$needle" "$d/acceptance" || { echo "$id: its approve fixture lacks $needle" >&2; exit 1; }; done; done'
check "AC7: for an issue in active/, approve from the main checkout finds its raft's worktree, records there and pushes nothing, and reads no other raft-named worktree" \
  lune run tests/run -- "$A/approve-raft.spec.luau"

finish
