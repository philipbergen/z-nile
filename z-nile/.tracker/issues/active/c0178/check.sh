#!/usr/bin/env bash
# Acceptance checks for c0178. SEQUESTERED: never edit during execution.
# One `check "ACn: ..."` per Checked acceptance criterion, in the same order as the issue doc.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" # physical: tests/run strips the physical cwd
source "$(git -C "$HERE" rev-parse --show-toplevel)/z-nile/lib/ac.sh" # cds to the item's project home
# sequestered specs: here before `./zn done`, promoted to its project's tests/acceptance/c0178 after it
A="$HERE/acceptance"
[[ -d $A ]] || A="$PWD/tests/acceptance/c0178"

# Work outside `check` is limited to running a spec through `tests/run` (which AC_LIST=1 list mode refuses),
# `./zn members` and other cheap reads; everything else goes inside `check`.
check "AC1: the image store keys an image by file bytes, names, executable bits, links, the harness code and a salt (a skipped path and the checkout's place decide nothing; a missing input is refused), builds it once, publishes it by one rename, does not wait for a lock whose owner is dead and waits for one whose owner is alive until it is stale, removes no image, builds one image for processes asking at once, and prunes only older images of its own kind" \
  lune run tests/run -- "$A/images.spec.luau"
check "AC2: engine.copy lays out what engine.build lays out from the tooling image in one cp (a plain cp where copy-on-write is refused), copies another tree as it is, puts the seed image's packs into a destination that is already a repository, and registers the fixture folder it copies into" \
  lune run tests/run -- "$A/tooling-image.spec.luau"
check "AC3: trackerfix.new clones the packed seed image into a bare origin and a main clone holding one seed commit authored by the fixture, with its seeded files, copy and executable paths and the skills' lessons unless noLessons, and makes the other clone, at the seed, when it is first used; it links nothing to the image, stays small, runs no cp, init or config, and counts what it starts and writes" \
  lune run tests/run -- "$A/seed-fixture.spec.luau"
check "AC4: a registered fixture folder is swept when its spec file passes and kept when a case failed, a folder that cannot be removed is shown and fails the run, the launcher prunes the images once before any spec starts, the runner prints the files written and processes started by the fixture helpers beside slowest:, and a spec's git init and git clone make no sample hook from a template of their own that a write is named for" \
  lune run tests/run -- "$A/harness.spec.luau"
check "AC5: clone.isolated clones this checkout's repository from a packed image of it, one per HEAD, sharing no object file with the repository or the image, and with paths (tooling) writes only the paths a spec reads, the staged tree after engine.empty being the full clone's" \
  lune run tests/run -- "$A/clone-image.spec.luau"
check "AC6: trackerfix.worktrees makes fresh named worktrees as ./zn worktree does, twenty of them with one tracker.sh run" \
  lune run tests/run -- "$A/worktrees.spec.luau"
check "AC7: fixture.git and fixture.exec check their directory once per call, read the home's physical path once per process, and still refuse a folder that is not a fixture repository before any git runs" \
  lune run tests/run -- "$A/fixture-check.spec.luau"
check "AC8: the thirteen cloning specs clone only their paths, the ten hand-built fixtures call trackerfix.new, and c0116/claims makes its worktrees with trackerfix.worktrees" \
  lune run tests/run -- "$A/overrides.spec.luau"
check "AC9: zz-test's Speed section and zz-arch's Layout name the fixture images, their store, their users and their key" \
  lune run tests/run -- "$A/docs.spec.luau"
check "AC10: the specs that build fixtures by trackerfix.new, by engine.copy, by clone.isolated and by hand, edited and not, and the fixture, architecture, fence and repository-fence rules, stay green (a sample; the merge's full gate runs all)" \
  lune run tests/run -- tests/acceptance/c0115/lessons.spec.luau tests/acceptance/c0114/compact-roots.spec.luau \
  tests/acceptance/c0114/publish-roots.spec.luau tests/acceptance/c0111/lessons-cli.spec.luau \
  tests/acceptance/c0053/commands-sync.spec.luau tests/acceptance/c0060/fixture.spec.luau \
  tests/acceptance/c0006/clone.spec.luau tests/acceptance/c0001/tracker-lifecycle.spec.luau \
  tests/acceptance/c0008/done-order.spec.luau tests/acceptance/c0038/deferred.spec.luau \
  tests/acceptance/c0116/promote.spec.luau tests/acceptance/c0120/promote-home.spec.luau \
  tests/acceptance/c0068/stop.spec.luau tests/acceptance/c0081/remap.spec.luau \
  tests/acceptance/c0058/fence.spec.luau tests/acceptance/c0049/parallel-runner.spec.luau \
  tests/tooling/fixture-elsewhere.spec.luau tests/tooling/audit-spec-left.spec.luau tests/tooling/gate-home-cache.spec.luau \
  tests/tooling/remap-once.spec.luau tests/tooling/worktree-fetch.spec.luau tests/tooling/repo-fence.spec.luau tests/meta/architecture.spec.luau

finish
