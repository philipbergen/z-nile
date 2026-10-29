# Review 001: R0063 (code mode)

Inputs: `5d262d835e79b3f6b70edbc69b4778026c1254c0` (`origin/main...HEAD`, raft `R0063.md` / `check.sh`, issue `c0172.md` / `check.sh` / `acceptance/*.spec.luau`, zz-rules / zz-arch / zz-test skills). `./zn sync --fetch` → `88818c79`. `./zn check c0172` → 4/4 PASS. `./zn promote-check R0063` → `promote-check OK`.

Grouped: [c0172@0b90651a5f8a]

### F1 [high] Execution modified sequestered acceptance (`cicd.spec.luau`), not an `active/` rename alone

Where: `git diff --find-renames=100% --name-status origin/main...HEAD -- '*/.tracker/**/check.sh' '*/.tracker/**/acceptance/**'` → `M z-nile/.tracker/issues/active/c0172/acceptance/cicd.spec.luau`; commit `af1f0649`.

Evidence: zz-review code mode item 2 requires that diff to list nothing except `R100` renames into `active/`. This branch adds a content edit in the issue’s sequestered acceptance folder during execution (comments plus `writtenVersion` / `place ~= nil`). The verification log records that `./zn promote-check R0063` failed on `37a81689` until that edit, then passed. I re-ran `./zn check c0172` and `./zn promote-check R0063` on `5d262d83`; both pass. The edit does not change mock-server behavior: `writtenVersion` is the same string previously stored in `saved.version` before the JSON response; for `^/universes/v1/(%d+)/places/(%d+)/versions$`, `universe ~= nil` implies `place ~= nil`, so the publish handler accepts the same POSTs as before.

Critique: Sequestered acceptance is the contract prep reviewed; execution is not allowed to rewrite it to satisfy RC0. The tempting fix is to treat the change as “type-check only” and land because the user asked to fix promote-check and merge.

Consequences: Accepting the edit without a prep move means any execution can patch sequestered specs when promote-check or `./zn check` fails, and reviewers lose a hard boundary between prep and raft work. The prep already recorded `./zn promote-check c0172` OK on a prototype while the readied blob still failed `./zn promote-check R0063` until this commit—so the gap is prep/promote-check on the exact blobs in `active/`, not the production scripts under test.

Recommendation: escalate to the user: either `z-stop` and re-prep so the type-check annotations land in prep (revert the execution edit to `acceptance/cicd.spec.luau`, re-ready, re-run execution), or explicitly accept a sequestration breach and document that decision outside this review (this round cannot approve with a high sequestration finding open). Do not stack further sequestered edits in this raft. Add prep discipline: run `./zn promote-check` on the member issue (or raft) against the exact acceptance files before `ready`, not only on a scratch prototype tree.

## Judged criteria (code mode only)

The issue document’s **Judged** section is empty; there are no Judged criteria to score.

Verdict: changes
