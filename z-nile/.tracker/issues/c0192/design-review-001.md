# Review 001: c0192 (design mode)
Inputs: worktree `prep-lesson-bound-every-probe` at a6aabd18 plus the uncommitted `c0192.md`, `check.sh` and `experiments/ref-lesson.md.txt`; c0191 at `origin/prep-no-leaked-processes` 88168bf6 (`c0191.md`, `acceptance/docs.spec.luau`, `experiments/ref-docs-draft.diff.txt`); c0193 and c0136 at `origin/main`; c0181 at `origin/prep-lessons-codify-consolidate` 70fa9f21; `./zn capture c0192`; `./zn check c0192` (0 of 4: no lesson file, "AGENTS.md carries no bounded-command rule (c0191 not landed?)", no Enforced by line, "not listed for --when design". These are the right reasons); `./zn lessons --skill zz-review --full`, `--when design --full`.

Scope fidelity: the captured outcome is the lesson, with its rule and check question, and it is delivered whole. The title and Problem are unchanged. The Non-goals came from b7b14ea1 (before this prep) and from the prep, and none of them drops an outcome. Decision 1 (a new lesson, not a sharpened one) holds: `git grep -lniE 'alarm|time limit|timeout|run_in_background|background (job|command)|leak|orphan|nohup|PPID' -- 'z-nile/skills/*/lessons/*.md' 'pickman/skills/*/lessons/*.md'` finds `probe-free-cli-lines-in-prep` (when to probe), `waiting-steps-show-liveness`, `count-calls-in-poll-loops`, `retire-keeps-what-readers-count` and a pickman-arch lesson. None of them carries "an agent's own commands are bounded". Overrides: none, confirmed. `lune run z-nile/affected` prints `ALL`, and `grep -rlF -e bound-every-probe -e zz-review/lessons z-nile/tests pickman/tests` finds only fixture paths (`c0111/prompt-lessons`, `c0111/lessons-cli`: `zz-review/lessons/both-kinds.md`). The rule sentence in the reference lesson matches c0191's `docs.spec` `RULE` byte for byte. No c0191 spec scans lesson files for `nohup`, `setsid` or `exec @ARGV`, apart from `probe-free-cli-lines-in-prep`.

### F1 [high] "Green in either landing order" is false: the Enforced by line names nothing c0181 accepts as a ref, and the design has no plan for c0181 landing first
Where: the Non-goals ("This lesson is written so that it is green in either landing order: it carries an **Enforced by** line in its body, which c0181's migration turns into the field"); Design 4; Chore checklist (c0181 is listed as a draft whose migration "will convert the Enforced by line, nothing here blocks it"); Maintainability.
Evidence: c0181 is `design: ready` on `origin/prep-lessons-codify-consolidate` (70fa9f21, `depends_on: [c0136]`). Nothing orders it against c0192. Its document says:
- "A ref is a repository-relative path and, for a spec, optionally ` :: "<case name>"` … a name ending `.spec.luau` is a **spec** (and must name a case); `z-nile/lints/<slug>.luau` is a **lint**; `z-nile/engine/rules/<slug>.luau` is a **rule** …; nothing else is a ref."
- Policy rule 3 adds: "the case is **named `[<this id>] …`** … A spec ref without a case, or a case not named for the lesson, is a problem."
- Policy rule 1 adds: "exactly one of `enforced_by` (with `enforced`) and `not_codifiable`".
- Under Gate: "`lessons (./zn lessons --check --policy)`", which every gate runs **unconditionally**.
- Its table row for c0192 expects "a lesson with `enforced_by` naming a `[zz-…]` case in c0191's spec".

Measured against that:
- Four of the five Enforced by paths (`z-nile/lib/bounded.pl`, `scripts/hooks/pre-bash.sh`, `z-nile/engine/reap.luau`, `AGENTS.md`) are not refs of any kind.
- The fifth, `z-nile/tests/acceptance/c0191/docs.spec.luau`, has no case named for this lesson. A search of every c0191 acceptance spec for `[zz-` (`git show origin/prep-no-leaked-processes:<each acceptance file> | grep -nF '[zz-'`) finds nothing; its cases are named `AC6: …`. Its specs are sequestered and then promoted, so nobody can add such a case later.

So the migration the design relies on has nothing to convert, in either order:
- **c0181 first:** the new lesson arrives with no state, and z-nile's full gate goes red on `--check --policy`. AC4 runs only `./zn lessons --check`, so `./zn check c0192` stays 4 of 4 while the merge gate fails, and the executor has no step to follow.
- **c0192 first:** c0181's executor has to write the enforcing case itself, which c0181's row assumes already exists in c0191.

c0193 met the same situation (its design review 004 F2). It wrote its own `z-nile/tests/meta/scanning-loops.spec.luau` with a `[zz-arch/scanning-loops-advance] …` case, and gave the c0181-first order a branch: `enforced_by` plus `enforced: part` plus a `- codify` harvest line.
Critique: the design promises something on c0181's behalf that c0181's own document contradicts. The tempting fix is to reword the Non-goal ("c0181 will decide"). That leaves the red gate in the c0181-first order, and it leaves c0181's expectation unmet by both issues.
Consequences: a lesson-named case needs a home that every gate runs and that c0181 may still edit, so not `tests/acceptance/`. That adds a Touched module and a dependency on c0191's `boundcmd` interface (`z-nile/engine/boundcmd.luau`, `check(command, ctx)`), whose names the executor must re-read at landing (as U1 already says for the five paths). The c0181-first branch adds two frontmatter keys (13 + 2 = 15 lines, inside AC1's 16) and a body cap of 1,200 bytes for `part` (the reference body is 1,147 bytes, measured with `awk` after the second `---`). The case's rule must be one that a fixture can break.
Recommendation: follow c0193's shape.
1. The executor writes `z-nile/tests/meta/bound-every-probe.spec.luau` with one case, `[zz-review/bound-every-probe] a bare probe is refused and the wrapped one passes, and the lesson carries AGENTS.md's rule`. It asserts three things:
   - `boundcmd.check` refuses `lune run probe.luau` and names `./zn run --time`;
   - it lets `./zn run --time 60 -- lune run probe.luau` through;
   - the sentence AGENTS.md carries is in the lesson (this also answers F2).
2. Name that case on the Enforced by line beside the files.
3. Add the c0181-first branch: `enforced_by: z-nile/tests/meta/bound-every-probe.spec.luau :: "[zz-review/bound-every-probe] …"`, `enforced: part` (the check's "did I write it through the wrapper where the hook can't read it" clause stays judged), and a `- codify zz-review/bound-every-probe: <ref> mutant: boundcmd lets a bare lune run through` line.
4. Add a `check.sh` AC that the meta file holds an `it(` with that name, and that `lune run tests/run -- tests/meta/bound-every-probe.spec.luau` passes (or leave the run to the gate, and pin only the name).
5. Add Rules-and-mutants rows: a permissive `boundcmd`, and a lesson sentence that drifts from AGENTS.md.
6. Tell c0181's lead that its c0192 row should name the meta case, not "a case in c0191's spec".
Lesson: z-design/quote-other-preps-before-promising

### F2 [medium] The pins the design calls permanent end at `done`: after that, the restated sentence and the five paths can drift silently
Where: Design 4 ("A lesson that names an enforcer which later moves fails this check and is edited, instead of rotting"); Chore checklist, Restated rules ("a later change of the sentence … fails this check until the lesson moves too"); Maintainability ("The next change to the mechanism moves the lesson's Enforced by line through AC3's file-exists check").
Evidence: AC2 and AC3 live in `check.sh`, which runs at `./zn check c0192` and at `done`, then never again (zz-review/recommendations-pick-spec-or-check: "a check.sh AC runs at the item's own check and `done`, then never again").
- c0191's `docs.spec` `PLACES` lists AGENTS.md and four skills, not this lesson. A later edit of the sentence in those five places keeps every gate green and leaves the lesson teaching the old wording.
- c0180 is named in c0191's own document as possibly moving `reap` into `z-nile/engine/cmd/`. That move, or any later rename of `reap.luau`, leaves a dead path on the Enforced by line, and no check fails.
Critique: z-design/restated-rules-move-together asks "is the new wording pinned?" The design says yes, but the pin expires. The tempting fix is a promoted acceptance spec. Design 5 rightly rejects that, because c0181 trims lesson bodies and a promoted spec can't move with it.
Consequences: a pin that outlives `done` but stays editable by c0181 has to live outside `tests/acceptance/`. That is the meta case of F1. If it reads AGENTS.md and the lesson as text, it has to cut the sentence out the way AC2 does (from the first `Run every probe` to the first `when you do.`), and it has to fail, not pass, when AGENTS.md has no such sentence (zz-test/no-vacuous-pass).
Recommendation: put the sentence comparison, and the existence of every path on the Enforced by line, in the F1 meta case, so every gate holds them. Keep AC2 and AC3 as the sequestered twins (the c0193 pattern). Correct the three claims so they say what runs when. Add the mutants "AGENTS.md's sentence edited after done (meta case red)" and "an enforcer moved (meta case red)".
Lesson: z-design/restated-rules-move-together

### F3 [low] The harvest note is fixed text that c0136's attribution rule will list as unattributed
Where: Design 6 and Implementation step 3 (`- note a code review's probes ran 14 h at 100% CPU on three cores (PR #125): zz-review/bound-every-probe`).
Evidence: c0136 (`design: ready` on origin/main, and a dependency of c0181) defines `lessons.unattributed` as "`<item> note <text>`, for every entry with no `erred`". It adds `--unattributed <id>` to z-design 5.5 and to zz-execute Phase 5 step 3. If c0136 lands first, the executor's Phase 5 lists this note. c0112 later makes `--unattributed` a gate stage.
Critique: harvest.md is not sequestered, so the executor can fix this, but the design hands them a fixed line and doesn't say so.
Consequences: the group has to name a skill that `lessons --check` accepts for this lesson's filing (`zz-review`, which is also where the lesson lives).
Recommendation: in step 3, add "if c0136 has landed, end the note's text with `(erred zz-review)`", and run `--unattributed c0192` beside `--uncovered` in step 4.

### F4 [low] The check question says "within a minute", while c0191 sanctions limits up to an hour, and How to apply never says when a longer one is right
Where: the reference lesson's `check:` and **How to apply** (`./zn run --time 60 -- <command>`); c0191's Design 2 ("Waits of up to an hour go through `./zn run --time 3600`"). c0191 also prescribes `--time 600` for `runtime-test`, `--time 900` for `mutants.py` and `--time 1800` for `cicd`.
Evidence: an agent that runs c0191's own `./zn run --time 1800 -- lune run scripts/cicd` answers "no" to this lesson's question. An agent that takes How to apply literally kills `runtime-test` at 60 s and, following the lesson, reports it as a hang.
Critique: the captured question keeps "within a minute", and that is the user's text, so it stays. The fix is detail in How to apply, not a reword of the check.
Recommendation: add half a sentence to How to apply (no new line, so AC1's 16 lines hold): "a command known to run longer (a gate-sized run, `runtime-test`, a mutation run) gets the limit its step names, never an open one". Optionally add an AC3 word that pins it.

### F5 [low] How to apply's command and exit codes are not pinned, though Design 3 lists them as content
Where: Design 3 ("**How to apply** (the exact command, the exit codes 124 and 125, never get round the hook)"); check.sh AC3's word list (`PR #125`, `14 h`, `alarm`, `launcher`).
Evidence: a lesson whose How to apply reads `nohup ./zn run --time 60 -- <cmd> &`, or that swaps 124 and 125, passes all four ACs. AC2 pins only the rule sentence.
Recommendation: add `124 (wall clock)`, `125 (CPU)` and `never get round the hook` to AC3's word list, with a mutant row for the swapped codes (z-design/spec-design-correspondence).

### F6 [low] E6 is an unfilled placeholder
Where: Unknowns & experiments, "**E6 (finished.spec on a simulated done)**: result recorded below once the run ends." No result follows.
Evidence: I read `rewrites.literals`: words that start with `$` are skipped, and grep patterns are marked. So the `"$ZN_ROOT/…"` paths and `skills/zz-review/lessons/bound-every-probe.md` (it resolves from `z-nile/` once written) look safe. I didn't run it (machine load 52).
Recommendation: record the run's result, or replace E6 with the reasoning above and mark it `reasoned`.

Candidate lesson (for the lead, not written by me): z-design: a lesson issue that says it is "green in either landing order" with an in-flight lesson-format issue (c0181, c0136) quotes that issue's current ref and entry rules and shows each order's state, because c0192 named prose files as enforcers that c0181's policy rejects; check: does each line I expect another prep's migration to convert parse as a ref under that prep's current document?

Verdict: changes
