# Review 002: R0131 (final mode)
Inputs: branch R0131/1/d0297 at 7a517f7a8 ("R0131: trace on the restacked finish"), on d0297's finish commit 47e16da5c90f06422a07fa307a8797c4a0c555fe. The stack's base is origin/main 055f3acb2 (the merge-base equals origin/main after `git fetch -q origin main`, fetch only). Also read: `git diff origin/main...HEAD`; the committed `trace.md`; R0131.md and its check.sh; review-001.md, refute-001.md, final-review-001.md, final-refute-001.md and harvest.md; d0297.md, its check.sh, acceptance/ (select.spec, cli.spec, watch.txt), proofs/finish.spec and results.txt; `z-nile/engine/stack.luau` (`rebaseUpstream`, to judge the new lesson).

Checks the reviewer ran:
- `./zn trace R0131 --check` at 23:24 PST on 2026-11-17 printed `ok: R0131` (exit 0). Final-review-001's F1 is closed: the layer now sits on origin/main, and `Commit:` names the finish commit. The two commits after it, 9b5e84a8e and 7a517f7a8, change only `trace.md`, `final-refute-001.md`, `spend.md` and a spend row.
- `./zn check d0297`: 4/4 PASS. No REPOSITORY CHANGED, and the tree was clean afterwards.
- From z-nile's home, `own-acceptance-callers`, `select-scope`, `watch` and `c0165/select` ran 17 passed, 0 failed.
- `./zn promote-check R0131`: OK.
- The captured reproduction, under `./zn run --time 60`, now prints nothing. That covers `lune run z-nile/affected -- <d0297 acceptance/cli.spec> <proofs/finish.spec>` and `-- --project z-nile <acceptance/select.spec>`.
- On this real layer branch, the gate's form `lune run z-nile/affected -- --project z-nile` prints 261 specs and none under `.tracker`. With `--own-acceptance` it adds exactly `.tracker/issues/active/d0297/acceptance/cli.spec.luau` and `select.spec.luau`, and not `proofs/`. That is the finish behaviour, seen on the real layer and not only in a fixture.
- Sequestration: the tracker `check.sh` and `acceptance/**` diff lists only `A …/d0297/acceptance/watch.txt`, which finish writes. It names exactly the three changed source files.
- Base movement: from the old base b89af8654 to 055f3acb2, main gained tracker files, `z-nile/next` and one lesson. It gained no source, spec or cited path, so no cited line moved.

Substance, judged row by row:
- **P1**: the design cells (d0297.md 18, 28, 44, 57 and 84) carry the Problem, the rule, the gate never passing the flag, and the prep-branch outcome. select.luau 208-213 is the filter, 238-240 the gate's view without `own`, and main.luau 4085 the one flag.
- **AC1**: `sel.affected` keeps a `watch.select` result only when `projects.rootOf` finds no root (select.luau 208-213). It then adds `own` once, deduplicated through `kept` (214-220), and applies the unchanged `only` filter and home-relative form to both (221-227). `sel.scope` clones the context with `own = nil` (238-240). The cited cases at select.spec 45, 70 and 77 are the cases they name. The own-list case opens `it(` on its own line, so the trace cites it through check.sh:12, and results.txt lists it green.
- **AC2**: affected.luau 44-45 parses the flag and 170-172 sets `own = current` only under it. `currentSpecs` already applies the layer's watch gate, so `own` is exactly the list the layer branch selected before d0297 (a promoted spec in it is deduplicated). main.luau 4085 is the only engine argv that carries the flag. `git grep` finds it in no gate, hook or forwarder. The tooling spec's case at line 65 checks this, and so does cli.spec:118.
- **AC3**: the pinned proof runs from check.sh:14. This layer's own results.txt lists both acceptance specs with their cases, which is the same behaviour on the real stack.
- **AC4**: affected.luau 9-10 is the usage line in the required form. zz-test lines 54 and 85 carry both sentences, and check.sh:15 greps them.
- **AC5 and AC6**: both are vacuous ("None.") and their cells say so in words. AC6's note maps the captured prep-branch outcome to AC2's proof, and affected.luau 180-184 prints only what the selection holds.
- **Source files**: the three changed source files are all accounted for. Nothing extra is in the diff. Besides the source files it holds the tooling spec and its watch file (10 paths, the review-001 widening), the zz-test edit, d0297's and R0131's records, the new zz-execute lesson and notes on two existing lessons.
- **Lessons**: the new `zz-execute/unfinished-layer-tip-is-not-the-finish` (`when: build`) is accurate. `rebaseUpstream` walks the rows oldest first, so with an `R<id>: ` tip it returns the parent of the `tracker: start` mark or of the first `<issue>: ` commit, which replays the whole layer, as the workaround says. A different raft could fail the same way. Both notes generalise their incidents into a question.

Scope fidelity: the Problem is the capture's word for word. The capture's three outcomes each have a Design and a Checked criterion: the gate never runs a sequestered spec (AC1, AC2), `--affected` on a prep branch is green when only those changed (AC2, via the gate's spec stage), and a spec case pins it (select.spec and cli.spec, promoted at done). Nothing was narrowed.

No findings.

Verdict: approve
