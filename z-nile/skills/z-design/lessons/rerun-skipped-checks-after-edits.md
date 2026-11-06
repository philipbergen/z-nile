---
title: Rerun the checks the runner skips after every edit they guard
when: design
tags: [acceptance, types, process]
check: Which checks for this draft does the test runner not run (a type check, a promotion dry run, a lint, a format check), and has each been rerun since the last edit it guards?
---
Some checks pass once and are never run again, because the everyday loop (running specs) does not include them. An edit made after that single run can break them silently, and the breakage surfaces only when someone (the executor, CI, `done`) finally runs them, often where it can no longer be fixed.

**Why:** R0040 design review 2 (F1): z-design runs `promote-check` once, in step 4. Round 1's answers added a field to a type and a two-argument `t.expect`. All 32 spec cases still passed, because the runner does not type-check, but `promote-check` (and with it RC0, which the executor may not fix) failed.

**How to apply:** list the checks the runner skips for the files this draft changes, and put each one's rerun in the step that edits those files (for sequestered specs: z-design step 5.3).

Run those checks before committing to a branch other agents read, not after: in c0115's round 4 the promotion type check caught a two-value `string.find` passed to `t.expect`, but only after the commit holding it had been read by another agent.

c0118 design review 008 F1: a spec case added in answer to round 006 passed `string.find`'s two returns into `t.expect`; two later rounds ran the spec but never the promotion dry run, so the type error stayed hidden behind the gate's `.tracker/**` ignore until a reviewer placed the specs where `done` puts them. After every round's answers, type-check, format and lint the changed specs where `done` will put them (or run `./zn promote-check` once a raft exists).
**Note** (R0063 review 001 F1): c0172 recorded `./zn promote-check` OK on the prototype, and the readied `cicd.spec.luau` was that file, but promotion on the execution tree failed two type errors (an upvalue left `Saved?`, a `string.match` capture left `string?`) while the runtime spec stayed green. Rerun `./zn promote-check` on the issue after the last edit of its acceptance specs, against those bytes, and record that run.

c0170 design review 003 F1: a refute rewrote prototype code after the last full gate, and its type step broke; the design still quoted the earlier green run. After a refute rewrites prototype code or a check.sh, rerun the full gate (every project, the type step included) and date the result.

c0239 design review 005 F1: a round's answer edited a sequestered spec's fixture (a base-commit `default.project.json` written as `{ "name": "pickman" }`, not a valid Rojo project) and nobody reran the spec, so three cases failed against a correct implementation while the Rules rows still said `run`. Before writing `run`, check that the prototype run is later than the last edit of its spec, and rerun the spec on the final bytes after any fixture edit.
